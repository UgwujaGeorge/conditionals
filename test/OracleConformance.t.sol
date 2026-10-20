// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Conditionals} from "../src/Conditionals.sol";
import {IIntake} from "../src/interfaces/IIntake.sol";
import {IOracleAttestation} from "../src/interfaces/IOracleAttestation.sol";
import {MockIMD, MockIntake} from "./utils/Mocks.sol";

/// @title The oracle-consumer conformance test, adapted to Conditionals
/// @notice The protocol's vector values, its digest and a signature made by the protocol's own signer tie this
///         contract's verification to what the oracle actually signs. Self-signed tests cannot: a struct, type
///         string or domain that differs from the protocol's passes them and fails here.
contract OracleConformanceTest is Test {
    // ---- the protocol's vector: do not change these ----
    uint256 constant VECTOR_CHAIN = 11155111;
    address constant VECTOR_CONSUMER = 0x0000000000000000000000000000000000002748;
    bytes32 constant VECTOR_DIGEST = 0x95fefa8b7c529852f4e2b6aec888930eb2bf5078e6443a85808e36df19e1325c;
    bytes constant VECTOR_SIGNATURE =
        hex"a26b14918607eb565af126beb54d3c5d19e923c41506def500b3521a4f9aa6d603ab44fd22f15dd2191732961a7131e4641244add8b0f09f20e6ae64381be8481b";
    /// @dev anvil's second account: the vector's attester. A test key, never a real one.
    address constant SIGNER = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    uint256 constant SIGNER_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint64 constant ISSUED_AT = 1800000000;
    uint64 constant EXPIRES_AT = 1800003600;

    /// @dev The callback's canonical signature. Its selector is what the intake calls.
    string constant CALLBACK =
        "onOracleResult(bytes32,(bytes32,uint256,bytes32,uint8,bytes,uint256,uint64,uint64,bytes32,bytes32,uint16,uint16,uint16,uint64,uint64),bytes)";

    MockIMD imd;
    MockIntake intake;
    Conditionals c;
    address owner = makeAddr("owner");
    address feeRecipient = makeAddr("fee");
    address creator = makeAddr("creator");

    function setUp() public {
        vm.chainId(VECTOR_CHAIN);
        vm.warp(ISSUED_AT);
        vm.roll(26_000_000);
        imd = new MockIMD();
        intake = new MockIntake();
        deployCodeTo(
            "Conditionals.sol:Conditionals",
            abi.encode(owner, IERC20(address(imd)), IIntake(address(intake)), SIGNER, feeRecipient),
            VECTOR_CONSUMER
        );
        c = Conditionals(VECTOR_CONSUMER);
        imd.mint(creator, 10 ether);
        vm.prank(creator);
        imd.approve(address(c), type(uint256).max);
    }

    /// @dev The vector attestation: a `bytes32[]` answer with one element, figure 12345, blocks 100-200, a panel of
    ///      five with a quorum of four that agreed unanimously.
    function vector() internal pure returns (IOracleAttestation.Attestation memory a) {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = bytes32(uint256(1));
        a = IOracleAttestation.Attestation({
            requestId: 0x0000000000004000800000000000000100000000000000000000000000000000,
            chainId: 1,
            questionHash: 0x2117f4362ebfa37aa8a8c0fed548604fe09ac46faf8ae7559cd64780f26a46fb,
            answerType: 5,
            answer: abi.encode(ids),
            figure: 12345,
            fromBlock: 100,
            toBlock: 200,
            blockHash: bytes32(uint256(7)),
            panelJobId: 0x0000000000004000800000000000000200000000000000000000000000000000,
            panelSize: 5,
            quorum: 4,
            agreed: 5,
            issuedAt: ISSUED_AT,
            expiresAt: EXPIRES_AT
        });
    }

    /// @notice The digest this contract verifies is the one the oracle signs.
    function test_digestMatchesTheProtocol() public view {
        assertEq(
            c.attestationDigest(vector()), VECTOR_DIGEST, "struct, type string or domain differs from the protocol's"
        );
    }

    /// @notice The callback's selector is the one the intake calls.
    function test_callbackSelectorIsCanonical() public view {
        assertEq(c.onOracleResult.selector, bytes4(keccak256(bytes(CALLBACK))), "callback parameters differ");
        assertEq(c.onOracleResult.selector, bytes4(0x510379c7));
    }

    /// @notice The protocol's own signature verifies against the digest this contract computes, the way the
    ///         contract verifies it. (The vector's answer type is bytes32[], which a bool market refuses, so the
    ///         delivered path is exercised with a fresh bool answer from the same key below.)
    function test_protocolSignatureVerifiesAgainstTheContractsDigest() public view {
        bytes32 digest = c.attestationDigest(vector());
        assertEq(ECDSA.recover(digest, VECTOR_SIGNATURE), SIGNER);
        assertTrue(SignatureChecker.isValidSignatureNow(SIGNER, digest, VECTOR_SIGNATURE));
    }

    /// @notice A fresh signature from the vector's key, delivered the way the writer delivers it, is accepted.
    function test_acceptsAFreshSignatureFromTheVectorKeyAsDelivered() public {
        uint64 closeTime = uint64(block.timestamp + 1 hours);
        uint64 resolveTime = uint64(block.timestamp + 2 hours);
        vm.prank(creator);
        uint256 id = c.createMarket(
            "The Clarity Act is signed into US law",
            "ETH closes above 5000 USD on Coinbase on 2026-12-01",
            "Use congress.gov for the law and the Coinbase ETH-USD daily close for the price.",
            closeTime,
            resolveTime,
            1 ether
        );
        vm.warp(resolveTime);
        uint256 windowBlock = block.number - c.WINDOW_DEPTH();
        assertEq(c.requestResolution(id), 2);
        bytes32 requestId = intake.requestIds(0);

        IOracleAttestation.Attestation memory a = vector();
        a.requestId = keccak256("another request");
        a.questionHash = keccak256(bytes(c.questionDocument(id, 0, windowBlock)));
        a.answerType = 0;
        a.answer = abi.encode(true);
        a.fromBlock = uint64(windowBlock);
        a.toBlock = uint64(windowBlock);
        a.issuedAt = resolveTime;
        a.expiresAt = resolveTime + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, c.attestationDigest(a));
        assertTrue(intake.complete(requestId, abi.encode(a, abi.encodePacked(r, s, v))), "not delivered under 200k gas");
        assertEq(c.getMarket(id).answers[0], 1);

        // The same answer signed by another key is refused.
        a.requestId = keccak256("yet another request");
        (v, r, s) = vm.sign(0xB0B, c.attestationDigest(a));
        assertFalse(
            intake.deliverRaw(
                address(c),
                abi.encodeWithSelector(c.onOracleResult.selector, intake.requestIds(1), a, abi.encodePacked(r, s, v))
            )
        );
    }
}
