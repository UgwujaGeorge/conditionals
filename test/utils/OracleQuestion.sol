// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @dev Copied from the oracle-consumer skill's REFERENCE.md (`OracleQuestion.sol`); only the answer-type codes
///      are inlined from `OracleAttestation` so the library stands alone. Test-only: the reference the contract's
///      hand-built question document is checked against.
library OracleAttestationCodes {
    uint8 internal constant ANSWER_BOOL = 0;
    uint8 internal constant ANSWER_ADDRESS = 1;
    uint8 internal constant ANSWER_BYTES32 = 2;
    uint8 internal constant ANSWER_UINT256 = 3;
    uint8 internal constant ANSWER_ADDRESS_LIST = 4;
    uint8 internal constant ANSWER_BYTES32_LIST = 5;
}

/// @notice Every attestation signs a `questionHash`: keccak-256 of the canonical question document,
/// which holds the question, its chain, its block window, its answer type and its definitions. A
/// contract that computes that hash itself, before it asks, can refuse every answer to any other
/// question. Store the hash beside the pending request and compare `a.questionHash` in the
/// callback: the signature then says which request the answer is for, and an answer paired with
/// the wrong request, by mistake or on purpose, is refused rather than acted on.
///
/// The hash is known in advance only for an absolute window (`{"fromBlock", "toBlock"}`) on the
/// question's chain, whose last block is at least five blocks deep when the plane reads the ask.
/// A relative window (`{"hours": N}`) resolves to blocks only then. On an Arbitrum chain, which
/// Robinhood Chain is, `block.number` is an Ethereum block number: read the chain's own from
/// `ArbSys(address(100)).arbBlockNumber()`.
///
/// This computes the hash; it does not judge whether the plane accepts the question. Check a body
/// with a real subject in it at `POST /requests/check` before a contract is deployed with it.
///
/// @dev The Solidity half of `questionDocument` and `canonicalize` in `@identitymd/protocol`:
/// object keys sorted, strings as `JSON.stringify` writes them, integers in decimal. The same
/// documents and hashes are pinned in `test/OracleQuestion.t.sol` and in the protocol package's
/// `test/oracle.test.ts`, so a change to either half fails a test before anything is signed.
///
/// It refuses what it cannot reproduce exactly, rather than hash bytes the plane will never hash:
/// - text outside ASCII. The plane reads a body's bytes as UTF-8, replacing what is not, and only
///   ASCII is checked here;
/// - a value that is exactly an address or a 32-byte hex string with an uppercase digit. The intake
///   lowercases such a value before anything reads it; hex inside longer text is left as written;
/// - definitions out of order. The document sorts its keys, so they are taken already sorted,
///   byte by byte, which is JavaScript's order for ASCII keys; a repeated key is out of order too;
/// - a number above 2^53 - 1, which JSON cannot carry exactly to the plane.
library OracleQuestion {
    /// @dev One of the definitions the requester pins: what a word in the question means.
    struct Definition {
        string key;
        string value;
    }

    struct Question {
        string question;
        /// @dev The chain the question is about, and whose blocks the window counts.
        uint256 chainId;
        uint256 fromBlock;
        uint256 toBlock;
        /// @dev One of `OracleAttestation`'s `ANSWER_*` codes.
        uint8 answerType;
        /// @dev For a list answer: how many leading positions are used. Zero for none.
        uint8 head;
        /// @dev `"evidence": "panel"`, a fact that is not on any chain. False for chain evidence,
        /// the default, which the document leaves out.
        bool panelEvidence;
        /// @dev Ascending by key. Empty for none: then the body must leave `definitions` out too,
        /// since `"definitions": {}` is a member of the document.
        Definition[] definitions;
    }

    error UnsupportedCharacter(uint256 index);
    error NotLowercaseHex();
    error DefinitionsOutOfOrder(uint256 index);
    error UnknownAnswerType(uint8 answerType);
    error NumberTooLarge(uint256 value);
    error WindowReversed(uint256 fromBlock, uint256 toBlock);

    /// @dev The largest integer a JSON number carries exactly to the plane: `Number.MAX_SAFE_INTEGER`.
    uint256 internal constant MAX_SAFE_INTEGER = 9_007_199_254_740_991;

    bytes16 private constant HEX_DIGITS = "0123456789abcdef";

    /// @notice The `questionHash` an attestation for this question carries.
    function hash(Question memory q) internal pure returns (bytes32) {
        return keccak256(document(q));
    }

    /// @notice The canonical question document, the bytes `hash` covers.
    function document(Question memory q) internal pure returns (bytes memory) {
        return bytes.concat(_members(q), "}");
    }

    /// @notice A complete `oracle.request` body for this question: the document's members, then the
    /// panel and how long the answer stays valid. The body and the hash come from the same values,
    /// so the question the plane hashes is the question this contract pinned. A body that needs
    /// more members (`allowAmbiguous`, `toleranceBps`, `consumer`) is built the same way, with
    /// `jsonString` for any text.
    function body(Question memory q, uint256 panelSize, uint256 quorum, uint256 validForSeconds)
        internal
        pure
        returns (bytes memory)
    {
        return bytes.concat(
            _members(q),
            ',"panelSize":',
            _number(panelSize),
            ',"quorum":',
            _number(quorum),
            ',"validForSeconds":',
            _number(validForSeconds),
            "}"
        );
    }

    /// @notice `text` as `JSON.stringify` writes it, quotes included: a quote, a backslash and the
    /// control characters escaped, everything else as it is. Reverts on a byte outside ASCII.
    function jsonString(string memory text) internal pure returns (bytes memory quoted) {
        bytes memory raw = bytes(text);
        uint256 length = raw.length;
        // How many bytes the escapes add. Most text has none, and is copied whole below.
        uint256 added = 0;
        unchecked {
            for (uint256 i; i < length; ++i) {
                uint256 c = _byteAt(raw, i);
                if (c >= 0x80) revert UnsupportedCharacter(i);
                if (c < 0x20) added += _shortEscape(c) != 0 ? 1 : 5;
                else if (c == 0x22 || c == 0x5c) added += 1;
            }
        }
        if (added == 0) return bytes.concat('"', raw, '"');

        // Sized exactly by the count above, so every write lands inside it.
        quoted = new bytes(length + added + 2);
        unchecked {
            uint256 j = _put(quoted, 0, 0x22);
            for (uint256 i; i < length; ++i) {
                uint256 c = _byteAt(raw, i);
                if (c >= 0x20 && c != 0x22 && c != 0x5c) {
                    j = _put(quoted, j, c);
                    continue;
                }
                j = _put(quoted, j, 0x5c);
                if (c >= 0x20) {
                    j = _put(quoted, j, c);
                    continue;
                }
                uint256 letter = uint8(_shortEscape(c));
                if (letter != 0) {
                    j = _put(quoted, j, letter);
                    continue;
                }
                j = _put(quoted, j, 0x75);
                j = _put(quoted, j, 0x30);
                j = _put(quoted, j, 0x30);
                j = _put(quoted, j, uint8(HEX_DIGITS[c >> 4]));
                j = _put(quoted, j, uint8(HEX_DIGITS[c & 0x0f]));
            }
            _put(quoted, j, 0x22);
        }
    }

    /// @dev The byte at `i`, which the caller keeps below the length: no bounds check.
    function _byteAt(bytes memory raw, uint256 i) private pure returns (uint256 c) {
        assembly ("memory-safe") {
            c := byte(0, mload(add(add(raw, 0x20), i)))
        }
    }

    /// @dev Writes one byte at `at` and returns the next position.
    function _put(bytes memory out, uint256 at, uint256 c) private pure returns (uint256) {
        assembly ("memory-safe") {
            mstore8(add(add(out, 0x20), at), c)
        }
        return at + 1;
    }

    /// @dev The document without its closing brace, so a body can carry on from it. Keys in
    /// sorted order: answerType, chainId, definitions, evidence, head, question, v, window.
    function _members(Question memory q) private pure returns (bytes memory members) {
        if (q.fromBlock > q.toBlock) revert WindowReversed(q.fromBlock, q.toBlock);
        _checkHexValue(bytes(q.question));
        members = bytes.concat('{"answerType":"', _answerType(q.answerType), '","chainId":', _number(q.chainId));
        if (q.definitions.length > 0) members = bytes.concat(members, ',"definitions":', _definitions(q.definitions));
        if (q.panelEvidence) members = bytes.concat(members, ',"evidence":"panel"');
        if (q.head != 0) members = bytes.concat(members, ',"head":', _number(q.head));
        members = bytes.concat(
            members,
            ',"question":',
            jsonString(q.question),
            ',"v":1,"window":{"fromBlock":',
            _number(q.fromBlock),
            ',"toBlock":',
            _number(q.toBlock),
            "}"
        );
    }

    function _definitions(Definition[] memory definitions) private pure returns (bytes memory object) {
        object = "{";
        for (uint256 i; i < definitions.length; ++i) {
            if (i > 0 && !_sortsBefore(bytes(definitions[i - 1].key), bytes(definitions[i].key))) {
                revert DefinitionsOutOfOrder(i);
            }
            _checkHexValue(bytes(definitions[i].value));
            object = bytes.concat(
                object,
                i == 0 ? bytes("") : bytes(","),
                jsonString(definitions[i].key),
                ":",
                jsonString(definitions[i].value)
            );
        }
        object = bytes.concat(object, "}");
    }

    function _answerType(uint8 answerType) private pure returns (bytes memory) {
        if (answerType == OracleAttestationCodes.ANSWER_BOOL) return "bool";
        if (answerType == OracleAttestationCodes.ANSWER_ADDRESS) return "address";
        if (answerType == OracleAttestationCodes.ANSWER_BYTES32) return "bytes32";
        if (answerType == OracleAttestationCodes.ANSWER_UINT256) return "uint256";
        if (answerType == OracleAttestationCodes.ANSWER_ADDRESS_LIST) return "address[]";
        if (answerType == OracleAttestationCodes.ANSWER_BYTES32_LIST) return "bytes32[]";
        revert UnknownAnswerType(answerType);
    }

    function _number(uint256 value) private pure returns (bytes memory) {
        if (value > MAX_SAFE_INTEGER) revert NumberTooLarge(value);
        return bytes(Strings.toString(value));
    }

    /// @dev The intake's `lowercaseHexValues`: a value that is exactly `0x` and 40 or 64 hex digits is
    /// read in lowercase. One with an uppercase digit is refused here, where it would otherwise hash
    /// as written and never match.
    function _checkHexValue(bytes memory value) private pure {
        uint256 length = value.length;
        if ((length != 42 && length != 66) || value[0] != "0" || value[1] != "x") return;
        bool upper = false;
        for (uint256 i = 2; i < length; ++i) {
            uint8 c = uint8(value[i]);
            if (c >= 0x41 && c <= 0x46) upper = true;
            else if (!((c >= 0x30 && c <= 0x39) || (c >= 0x61 && c <= 0x66))) return;
        }
        if (upper) revert NotLowercaseHex();
    }

    /// @dev `JSON.stringify`'s two-character escapes: backspace, tab, newline, form feed, return.
    function _shortEscape(uint256 c) private pure returns (bytes1) {
        if (c == 0x08) return "b";
        if (c == 0x09) return "t";
        if (c == 0x0a) return "n";
        if (c == 0x0c) return "f";
        if (c == 0x0d) return "r";
        return 0;
    }

    /// @dev Strictly before, byte by byte, a prefix first.
    function _sortsBefore(bytes memory a, bytes memory b) private pure returns (bool) {
        uint256 shorter = a.length < b.length ? a.length : b.length;
        for (uint256 i; i < shorter; ++i) {
            if (a[i] != b[i]) return a[i] < b[i];
        }
        return a.length < b.length;
    }
}
