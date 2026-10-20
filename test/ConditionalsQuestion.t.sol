// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Conditionals} from "../src/Conditionals.sol";
import {Fixture} from "./utils/Fixture.sol";
import {OracleQuestion, OracleAttestationCodes} from "./utils/OracleQuestion.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @dev The contract writes its question document by hand. These tests check it against the protocol's own
///      `OracleQuestion` (copied from the oracle-consumer reference), which is itself pinned to the protocol vector,
///      so an escaping, ordering or member mistake in either copy fails here before an ask is paid for.
contract ConditionalsQuestionTest is Fixture {
    using Strings for uint256;
    using Strings for address;

    /// @dev The protocol's vector for `OracleQuestion`: the questionHash of the conformance attestation.
    function test_referenceLibraryReproducesTheProtocolVector() public pure {
        OracleQuestion.Question memory q;
        q.question = "Which Uniswap v4 pool did the most WETH volume in the last day?";
        q.chainId = 1;
        q.fromBlock = 100;
        q.toBlock = 200;
        q.answerType = OracleAttestationCodes.ANSWER_BYTES32_LIST;
        q.head = 1;
        q.definitions = new OracleQuestion.Definition[](1);
        q.definitions[0] =
            OracleQuestion.Definition("denomination", "WETH, summed as the absolute swapped amount on the WETH side");
        assertEq(OracleQuestion.hash(q), 0x2117f4362ebfa37aa8a8c0fed548604fe09ac46faf8ae7559cd64780f26a46fb);
    }

    /// @dev The live-API vector (POST /requests/quote, 2026-10-20) is reproduced by the protocol library as well as by
    ///      the contract, so the two agree on a document the plane actually hashed.
    function test_liveApiVectorAgreesWithTheReferenceLibrary() public {
        vm.warp(1_760_000_000);
        vm.prank(creator);
        uint256 id = c.createMarket(
            "The US Federal Reserve announced a cut to the federal funds target range at its September 2025 FOMC meeting",
            "Bitcoin closed above 100000 USD on Coinbase on 2025-10-01",
            "Use the official FOMC statements on federalreserve.gov and the Coinbase BTC-USD daily close (UTC).",
            uint64(1_760_000_100),
            uint64(1_760_000_200),
            1 ether
        );
        assertEq(address(c), 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a, "fixture address is part of the vector");
        bytes32 expected = 0xf02559bba7566c41440ea2c04c9c9f56372c3f5dc2288352f3e84d364fa8da7e;
        assertEq(OracleQuestion.hash(_reference(id, 0, 26_230_000)), expected);
        assertEq(keccak256(bytes(c.questionDocument(id, 0, 26_230_000))), expected);
    }

    /// forge-config: default.fuzz.runs = 512
    function testFuzz_documentMatchesTheReferenceLibrary(
        bytes memory conditionSeed,
        bytes memory outcomeSeed,
        bytes memory rulesSeed,
        uint32 windowBlock,
        uint32 resolveIn
    ) public {
        string memory condition = _text(conditionSeed, c.MAX_CONDITION_LENGTH(), false);
        string memory outcome = _text(outcomeSeed, c.MAX_OUTCOME_LENGTH(), false);
        string memory rules = _text(rulesSeed, c.MAX_RULES_LENGTH(), true);
        uint64 close = uint64(block.timestamp + 1);
        uint64 resolve = uint64(close + bound(resolveIn, 0, 700 days));
        vm.prank(creator);
        uint256 id = c.createMarket(condition, outcome, rules, close, resolve, 1 ether);

        for (uint8 q; q < 2; ++q) {
            bytes memory expectedDoc = OracleQuestion.document(_reference(id, q, windowBlock));
            assertEq(bytes(c.questionDocument(id, q, windowBlock)), expectedDoc, "document differs from the protocol's");
        }
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_bodyCarriesTheDocumentAndThePanelTerms(bytes memory outcomeSeed, uint32 windowBlock) public {
        string memory outcome = _text(outcomeSeed, c.MAX_OUTCOME_LENGTH(), false);
        vm.prank(creator);
        uint256 id = c.createMarket(CONDITION, outcome, RULES, closeTime, resolveTime, 1 ether);
        string memory body = c.requestBody(id, 1, windowBlock);
        assertLe(bytes(body).length, 16 * 1024, "body above the Intake's 16 KiB");

        OracleQuestion.Question memory q = _reference(id, 1, windowBlock);
        assertEq(vm.parseJsonString(body, ".answerType"), "bool");
        assertEq(vm.parseJsonUint(body, ".chainId"), 1);
        assertEq(vm.parseJsonString(body, ".evidence"), "panel");
        assertEq(vm.parseJsonString(body, ".question"), q.question);
        assertEq(vm.parseJsonString(body, ".definitions.rules"), RULES);
        assertEq(vm.parseJsonString(body, ".definitions.asOf"), q.definitions[0].value);
        assertEq(vm.parseJsonUint(body, ".v"), 1);
        assertEq(vm.parseJsonUint(body, ".window.fromBlock"), windowBlock);
        assertEq(vm.parseJsonUint(body, ".window.toBlock"), windowBlock);
        assertEq(vm.parseJsonUint(body, ".panelSize"), 5);
        assertEq(vm.parseJsonUint(body, ".quorum"), 4);
        assertEq(vm.parseJsonUint(body, ".validForSeconds"), 86_400);
        // The question's limits on the paid door.
        assertLe(bytes(q.question).length, 2000);
        assertLe(bytes(q.definitions[0].value).length, 512);
        assertLe(bytes(q.definitions[1].value).length, 512);
    }

    /// @dev The contract accepts exactly the text the canonical JSON carries without escapes: anything it accepts is
    ///      written by `JSON.stringify` as it is, and anything that would need an escape (or is not ASCII) is refused.
    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_acceptedTextNeedsNoEscaping(bytes memory raw) public {
        if (raw.length > c.MAX_CONDITION_LENGTH()) {
            assembly ("memory-safe") { mstore(raw, 280) }
        }
        bool plain = raw.length > 0;
        for (uint256 i; i < raw.length; ++i) {
            uint8 ch = uint8(raw[i]);
            if (ch < 0x20 || ch > 0x7e || ch == 0x22 || ch == 0x5c) plain = false;
        }
        vm.prank(creator);
        if (!plain) vm.expectRevert(Conditionals.InvalidText.selector);
        c.createMarket(string(raw), OUTCOME, RULES, closeTime, resolveTime, 1 ether);
        if (plain) assertEq(OracleQuestion.jsonString(string(raw)), bytes.concat('"', raw, '"'));
    }

    /// @dev The asked window is block.number - 10 at the time of the ask, and the stored hash is the hash of exactly
    ///      that document.
    /// forge-config: default.fuzz.runs = 256
    function testFuzz_askPinsTheDocumentOfTheWindowItAsked(uint32 blockNumber) public {
        uint256 n = bound(blockNumber, 11, type(uint32).max);
        uint256 id = _create();
        vm.warp(resolveTime);
        vm.roll(n);
        uint256 before = intake.count();
        c.requestResolution(id);
        for (uint8 q; q < 2; ++q) {
            bytes32 rid = intake.requestIds(before + q);
            (,, bool live, bytes32 questionHash) = c.asks(keccak256(abi.encode(address(intake), rid)));
            assertTrue(live);
            assertEq(questionHash, OracleQuestion.hash(_reference(id, q, n - 10)));
            assertEq(vm.parseJsonUint(string(intake.bodyOf(rid)), ".window.toBlock"), n - 10);
        }
    }

    // ---------------------------------------------------------------------------------------------------------------

    /// @dev Printable ASCII without `"` or `\`, 1 to maxLength bytes; with a space when `space`.
    function _text(bytes memory seed, uint256 maxLength, bool space) internal pure returns (string memory) {
        uint256 n = seed.length == 0 ? 1 : (seed.length > maxLength ? maxLength : seed.length);
        bytes memory out = new bytes(n);
        for (uint256 i; i < n; ++i) {
            uint8 b = i < seed.length ? uint8(seed[i]) : 0x41;
            uint8 ch = 0x20 + b % 93;
            if (ch >= 0x22) ++ch;
            if (ch >= 0x5c) ++ch;
            out[i] = bytes1(ch);
        }
        if (space) out[n / 2] = " ";
        return string(out);
    }

    /// @dev The question the contract asks, built with the protocol library.
    function _reference(uint256 id, uint8 question, uint256 windowBlock)
        internal
        view
        returns (OracleQuestion.Question memory q)
    {
        Conditionals.Market memory m = c.getMarket(id);
        q.question = string.concat(
            "Conditionals market ",
            id.toString(),
            " on Robinhood Chain contract ",
            address(c).toHexString(),
            ", ",
            question == 0 ? "condition" : "outcome",
            " statement. Was the following statement true as of unix time ",
            uint256(m.resolveTime).toString(),
            " (UTC)? Statement: ",
            question == 0 ? m.condition : m.outcome
        );
        q.chainId = 1;
        q.fromBlock = windowBlock;
        q.toBlock = windowBlock;
        q.answerType = OracleAttestationCodes.ANSWER_BOOL;
        q.panelEvidence = true;
        q.definitions = new OracleQuestion.Definition[](2);
        q.definitions[0] = OracleQuestion.Definition(
            "asOf",
            string.concat(
                "Judge the statement by what had happened by unix time ",
                uint256(m.resolveTime).toString(),
                " (UTC). Blockchain blocks are context only."
            )
        );
        q.definitions[1] = OracleQuestion.Definition("rules", m.rules);
    }
}
