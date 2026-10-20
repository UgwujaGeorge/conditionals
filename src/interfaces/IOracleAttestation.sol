// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The IdentityMD oracle's signed answer, EIP-712 domain {name: "IdentityMD Oracle", version: "2"}.
/// @dev https://imd.fun/docs/#oracle-the-attestation. `answer` is `abi.encode` of the value.
interface IOracleAttestation {
    struct Attestation {
        bytes32 requestId;
        uint256 chainId;
        bytes32 questionHash;
        uint8 answerType;
        bytes answer;
        uint256 figure;
        uint64 fromBlock;
        uint64 toBlock;
        bytes32 blockHash;
        bytes32 panelJobId;
        uint16 panelSize;
        uint16 quorum;
        uint16 agreed;
        uint64 issuedAt;
        uint64 expiresAt;
    }
}
