// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ConditionalsFacts as Facts} from "../src/ConditionalsFacts.sol";
import {IIntake} from "../src/interfaces/IIntake.sol";
import {IOracleAttestation} from "../src/interfaces/IOracleAttestation.sol";
import {MockIMD, MockIntake, MockSignerRegistry} from "./utils/Mocks.sol";
import {FactsFixture} from "./ConditionalsFacts.t.sol";

/// @dev An Intake that hands out the same request id every time, to exercise the duplicate-ask guard.
contract FixedIdIntake is IIntake {
    address public constant PAYEE = address(0xFEE5);

    function priceOf(bytes32, address) external pure returns (uint256) {
        return 0.5 ether;
    }

    function requestWithFailure(bytes32, bytes calldata, Callback calldata, bytes4, address asset, uint256 amount)
        external
        returns (bytes32)
    {
        IERC20(asset).transferFrom(msg.sender, PAYEE, amount);
        return keccak256("always the same id");
    }
}

/// @notice The oracle-consumer conformance vector, applied to ConditionalsFacts: deployed at the protocol's vector
///         address on the vector's chain, it must reproduce the protocol's digest and accept the protocol's signature.
contract ConditionalsFactsConformanceTest is Test {
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
    string constant CALLBACK =
        "onOracleResult(bytes32,(bytes32,uint256,bytes32,uint8,bytes,uint256,uint64,uint64,bytes32,bytes32,uint16,uint16,uint16,uint64,uint64),bytes)";
    string constant FAILURE = "onFailure(bytes32,uint8,bytes32,uint16,uint16,bytes)";

    MockIMD imd;
    MockIntake intake;
    Facts c;
    address creator = makeAddr("creator");

    function setUp() public {
        vm.chainId(VECTOR_CHAIN);
        vm.warp(ISSUED_AT);
        vm.roll(26_000_000);
        imd = new MockIMD();
        intake = new MockIntake();
        deployCodeTo(
            "ConditionalsFacts.sol:ConditionalsFacts",
            abi.encode(makeAddr("owner"), IERC20(address(imd)), IIntake(address(intake)), SIGNER, makeAddr("fee")),
            VECTOR_CONSUMER
        );
        c = Facts(VECTOR_CONSUMER);
        imd.mint(creator, 100 ether);
        vm.prank(creator);
        imd.approve(address(c), type(uint256).max);
    }

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

    function test_conformance_digestMatchesTheProtocol() public view {
        assertEq(c.attestationDigest(vector()), VECTOR_DIGEST, "struct, type string or domain differs");
    }

    function test_conformance_protocolSignatureVerifies() public view {
        bytes32 digest = c.attestationDigest(vector());
        assertEq(ECDSA.recover(digest, VECTOR_SIGNATURE), SIGNER);
        assertTrue(SignatureChecker.isValidSignatureNow(SIGNER, digest, VECTOR_SIGNATURE));
    }

    function test_conformance_callbackSelectorsAreCanonical() public pure {
        assertEq(Facts.onOracleResult.selector, bytes4(keccak256(bytes(CALLBACK))));
        assertEq(Facts.onFailure.selector, bytes4(keccak256(bytes(FAILURE))));
    }

    /// @dev The vector itself is a bytes32[] answer to a question this contract never asked: delivered for a live
    ///      ask it is refused, and the ask stays answerable by a fresh bool answer from the same key.
    function test_conformance_vectorRefusedThenFreshBoolAnswerAccepted() public {
        vm.prank(creator);
        uint256 id =
            c.createFact("Bitcoin", "Bitcoin supply is capped at 21 million", "Use the Bitcoin source.", 1 ether);
        uint256 windowBlock = block.number - 10;
        vm.prank(creator);
        bytes32 requestId = c.challenge(id, 1 ether);
        assertFalse(
            intake.deliverRaw(
                address(c), abi.encodeWithSelector(c.onOracleResult.selector, requestId, vector(), VECTOR_SIGNATURE)
            )
        );
        IOracleAttestation.Attestation memory a = vector();
        a.requestId = keccak256("fresh");
        a.questionHash = keccak256(bytes(c.questionDocument(id, 1, ISSUED_AT, windowBlock)));
        a.answerType = 0;
        a.answer = abi.encode(true);
        a.fromBlock = uint64(windowBlock);
        a.toBlock = uint64(windowBlock);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, c.attestationDigest(a));
        assertTrue(intake.complete(requestId, abi.encode(a, abi.encodePacked(r, s, v))), "not delivered under 200k");
        assertEq(c.getFact(id).verdict, 1);
    }
}

/// @notice Failure paths and binding checks beyond ConditionalsFacts.t.sol.
contract ConditionalsFactsFailurePathsTest is FactsFixture {
    // ---- binding an answer to its own question --------------------------------------------------------------------

    function test_answerToAnotherFactsQuestionIsRefused() public {
        uint256 one = _create();
        vm.prank(creator);
        uint256 two = c.createFact(TOPIC, "Ethereum moved to proof of stake in 2022", RULES, B);
        AskRef memory refOne = _challenge(carol, one);
        AskRef memory refTwo = _challenge(bob, two);

        // Fact two's genuine, correctly signed answer, delivered for fact one's request.
        IOracleAttestation.Attestation memory a = _attestation(two, refTwo, false);
        bytes memory sig = _sign(a, signerKey);
        vm.prank(address(intake));
        vm.expectRevert(Facts.BadAttestation.selector);
        c.onOracleResult(refOne.requestId, a, sig);

        // An answer to the same fact's question as of another time (a different round or ask) is refused too.
        a = _attestation(one, refOne, true);
        a.questionHash = keccak256(bytes(c.questionDocument(one, 1, refOne.askedAt + 1, refOne.windowBlock)));
        sig = _sign(a, signerKey);
        vm.prank(address(intake));
        vm.expectRevert(Facts.BadAttestation.selector);
        c.onOracleResult(refOne.requestId, a, sig);

        assertTrue(_answer(one, refOne, true));
        assertTrue(_answer(two, refTwo, false));
        assertEq(c.getFact(one).verdict, 1);
        assertEq(c.getFact(two).verdict, 2);
    }

    function test_signatureForAnotherConsumerOrChainIsRefused() public {
        uint256 id = _create();
        AskRef memory ref = _challenge(carol, id);
        IOracleAttestation.Attestation memory a = _attestation(id, ref, true);
        bytes32 structHash = _structHash(a);

        bytes32 otherContract = _typed(structHash, block.chainid, address(0xC0FFEE));
        bytes32 otherChain = _typed(structHash, 1, address(c));
        bytes32 v1Domain = keccak256(
            abi.encodePacked(
                "\x19\x01",
                keccak256(
                    abi.encode(
                        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                        keccak256("IdentityMD Oracle"),
                        keccak256("1"),
                        block.chainid,
                        address(c)
                    )
                ),
                structHash
            )
        );
        bytes32[3] memory wrong = [otherContract, otherChain, v1Domain];
        for (uint256 i; i < 3; ++i) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, wrong[i]);
            vm.prank(address(intake));
            vm.expectRevert(Facts.BadAttestation.selector);
            c.onOracleResult(ref.requestId, a, abi.encodePacked(r, s, v));
        }
        // An empty or malformed signature is refused, not a panic.
        vm.prank(address(intake));
        vm.expectRevert(Facts.BadAttestation.selector);
        c.onOracleResult(ref.requestId, a, "");
        vm.prank(address(intake));
        vm.expectRevert(Facts.BadAttestation.selector);
        c.onOracleResult(ref.requestId, a, new bytes(65));
        assertTrue(_answer(id, ref, true));
    }

    function test_answerBelowConfiguredQuorumIsRefusedEvenIfUnanimous() public {
        uint256 id = _create();
        AskRef memory ref = _challenge(carol, id);
        IOracleAttestation.Attestation memory a = _attestation(id, ref, true);
        a.panelSize = 5;
        a.quorum = 3;
        a.agreed = 5;
        _refuse(ref, a);
        a = _attestation(id, ref, true);
        a.answer = abi.encodePacked(uint8(1));
        _refuse(ref, a);
        a = _attestation(id, ref, true);
        a.answer = abi.encode(true, true);
        _refuse(ref, a);
    }

    function test_aLargerPanelThanAskedIsAccepted() public {
        uint256 id = _create();
        AskRef memory ref = _challenge(carol, id);
        IOracleAttestation.Attestation memory a = _attestation(id, ref, false);
        a.panelSize = 30;
        a.quorum = 20;
        a.agreed = 20;
        assertTrue(_deliver(ref, a, _sign(a, signerKey)));
        assertEq(c.getFact(id).verdict, 2);
    }

    function _refuse(AskRef memory ref, IOracleAttestation.Attestation memory a) internal {
        bytes memory sig = _sign(a, signerKey);
        vm.prank(address(intake));
        vm.expectRevert(Facts.BadAttestation.selector);
        c.onOracleResult(ref.requestId, a, sig);
    }

    // ---- timeouts --------------------------------------------------------------------------------------------------

    function test_answerAtExactlyTheTimeoutIsIgnoredAndOneSecondEarlierSettles() public {
        uint256 id = _create();
        AskRef memory ref = _challenge(carol, id);
        vm.warp(ref.askedAt + 1 days);
        assertTrue(_answer(id, ref, true));
        assertEq(c.getFact(id).verdict, 0, "ignored at the timeout");

        vm.roll(block.number + 5);
        AskRef memory again = _challenge(bob, id);
        vm.warp(again.askedAt + 1 days - 1);
        assertTrue(_answer(id, again, false));
        assertEq(c.getFact(id).verdict, 2);
        assertEq(uint8(_phase(id, 1)), uint8(Facts.Phase.Settled));
    }

    function test_closeAfterTimeoutThenTheLateAnswerAndFailureChangeNothing() public {
        uint256 id = _create();
        AskRef memory first = _challenge(carol, id);
        AskRef memory second;
        vm.warp(block.timestamp + 1 days);
        vm.prank(creator);
        uint256 refund = c.closeRound(id);
        assertGe(refund, c.getRound(id, 1).seed);
        vm.prank(bob);
        assertEq(c.openRound(id), 2);
        uint256 k = _buy(alice, id, 0, 2 ether);

        // The first round's late answer arrives during round two: it settles neither round.
        assertTrue(_answer(id, first, true));
        assertEq(uint8(_phase(id, 1)), uint8(Facts.Phase.Closed));
        assertEq(uint8(_phase(id, 2)), uint8(Facts.Phase.Open));
        assertEq(c.getFact(id).verdict, 0);
        assertEq(c.getRound(id, 1).makerBalance, 0);

        second = _challenge(carol, id);
        assertTrue(_answer(id, second, true));
        vm.prank(alice);
        assertEq(c.redeem(id, 2), k);
        // Round one closed with nothing held: it redeems nothing.
        vm.prank(alice);
        assertEq(c.redeem(id, 1), 0);
        _drainAll();
    }

    function test_failureAfterTimeoutStillResumes() public {
        uint256 id = _create();
        AskRef memory ref = _challenge(carol, id);
        vm.warp(block.timestamp + 2 days);
        assertTrue(intake.fail(ref.requestId, 2, "disagreed"));
        assertEq(uint8(_phase(id, 1)), uint8(Facts.Phase.Open));
        // A second delivery of the same failure, or an answer after it, finds no ask.
        vm.prank(address(intake));
        vm.expectRevert(Facts.UnknownAsk.selector);
        c.onFailure(ref.requestId, 2, "disagreed", 0, 0, "");
        IOracleAttestation.Attestation memory a = _attestation(id, ref, true);
        bytes memory sig = _sign(a, signerKey);
        vm.prank(address(intake));
        vm.expectRevert(Facts.UnknownAsk.selector);
        c.onOracleResult(ref.requestId, a, sig);
    }

    function test_failureForAnUnknownRequestFromTheIntakeIsRefused() public {
        uint256 id = _create();
        _challenge(carol, id);
        vm.prank(address(intake));
        vm.expectRevert(Facts.UnknownAsk.selector);
        c.onFailure(keccak256("someone else's"), 1, "body_invalid", 0, 0, "");
        assertEq(uint8(_phase(id, 1)), uint8(Facts.Phase.Asking));
    }

    function test_answerAfterSettlementByAnotherAskIsIgnored() public {
        uint256 id = _create();
        AskRef memory first = _challenge(carol, id);
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 5);
        AskRef memory second = _challenge(bob, id);
        assertTrue(_answer(id, second, true));
        // The first ask is still recorded live; its answer is ignored once the round is settled, and clears it.
        assertTrue(_answer(id, first, false));
        assertEq(c.getFact(id).verdict, 1);
        assertEq(c.getRound(id, 1).winner, 0);
        (,, bool live,) = c.asks(keccak256(abi.encode(address(intake), first.requestId)));
        assertFalse(live);
    }

    function test_duplicateRequestIdFromTheIntakeIsRefusedAtomically() public {
        FixedIdIntake fixedIntake = new FixedIdIntake();
        _rotate(
            Facts.OracleConfig({
                intake: IIntake(address(fixedIntake)),
                signer: signer,
                price: 0.5 ether,
                panelSize: 5,
                quorum: 4,
                action: bytes32("oracle.request@oracle-1")
            })
        );
        uint256 id = _create();
        _challenge(carol, id);
        vm.warp(block.timestamp + 1 days);
        uint256 before = imd.balanceOf(bob);
        vm.prank(bob);
        vm.expectRevert(Facts.DuplicateAsk.selector);
        c.challenge(id, 1 ether);
        assertEq(imd.balanceOf(bob), before, "nothing charged");
        assertEq(imd.allowance(address(c), address(fixedIntake)), 0);
        assertTrue(c.trading(id), "still trading after the timeout");
    }

    // ---- price handling --------------------------------------------------------------------------------------------

    function test_priceFallbacks() public {
        uint256 id = _create();
        intake.setPriceOfReverts(true);
        assertEq(c.challengePrice(id), 0.5 ether, "no priceOf: the configured price");
        intake.setPriceOfReverts(false);
        intake.setPrice(10 ether);
        assertEq(c.challengePrice(id), 10 ether, "MAX_PRICE itself is allowed");
        intake.setPrice(10 ether + 1);
        assertEq(c.challengePrice(id), 10 ether + 1, "above MAX_PRICE: the live price is quoted");
        // challenge refuses a live price above MAX_PRICE, whatever maxPrice allows; nothing is charged.
        uint256 before = imd.balanceOf(carol);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(Facts.PriceTooHigh.selector, 10 ether + 1, 10 ether));
        c.challenge(id, 100 ether);
        // maxPrice below MAX_PRICE is the cap.
        intake.setPrice(2 ether);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(Facts.PriceTooHigh.selector, 2 ether, 1 ether));
        c.challenge(id, 1 ether);
        assertEq(imd.balanceOf(carol), before);
        assertTrue(c.trading(id));

        intake.setPrice(0);
        vm.prank(carol);
        vm.expectRevert(bytes("ActionNotSold"));
        c.challenge(id, 100 ether);
        assertEq(imd.balanceOf(carol), before);
        assertEq(imd.allowance(address(c), address(intake)), 0);
    }

    function test_challengeWithoutFundsOrApprovalReverts() public {
        uint256 id = _create();
        address poor = makeAddr("poor");
        vm.prank(poor);
        vm.expectRevert();
        c.challenge(id, 1 ether);
        imd.mint(poor, 1 ether);
        vm.prank(poor);
        vm.expectRevert();
        c.challenge(id, 1 ether);
        assertTrue(c.trading(id));
        assertEq(intake.count(), 0);
    }

    function test_challengeLeavesNoAllowance() public {
        uint256 id = _create();
        _challenge(carol, id);
        assertEq(imd.allowance(address(c), address(intake)), 0);
        assertEq(imd.balanceOf(address(c)), c.getRound(id, 1).makerBalance, "the price was forwarded, not kept");
    }

    // ---- owner powers ----------------------------------------------------------------------------------------------

    function test_owner_cannotRedirectAnOpenRoundsAnswers() public {
        uint256 id = _create();
        uint256 newKey = 0xBEEF;
        _rotate(
            Facts.OracleConfig({
                intake: IIntake(address(intake)),
                signer: vm.addr(newKey),
                price: 0.5 ether,
                panelSize: 5,
                quorum: 4,
                action: bytes32("oracle.request@oracle-1")
            })
        );
        AskRef memory ref = _challenge(carol, id);
        IOracleAttestation.Attestation memory a = _attestation(id, ref, false);
        bytes memory sig = _sign(a, newKey);
        vm.prank(address(intake));
        vm.expectRevert(Facts.BadAttestation.selector);
        c.onOracleResult(ref.requestId, a, sig);
        assertTrue(_answer(id, ref, true), "the round's own signer still answers");
        assertEq(c.getFact(id).verdict, 1);
    }

    function test_owner_configValidation() public {
        Facts.OracleConfig memory ok = c.oracleConfig();
        Facts.OracleConfig memory bad;
        vm.startPrank(owner);

        bad = _copy(ok);
        bad.intake = IIntake(address(0));
        vm.expectRevert(Facts.ZeroAddress.selector);
        c.proposeOracleConfig(bad);
        bad = _copy(ok);
        bad.signer = address(0);
        vm.expectRevert(Facts.ZeroAddress.selector);
        c.proposeOracleConfig(bad);

        bytes4 invalid = Facts.InvalidConfig.selector;
        bad = _copy(ok);
        bad.action = bytes32(0);
        vm.expectRevert(invalid);
        c.proposeOracleConfig(bad);
        bad = _copy(ok);
        bad.price = 0;
        vm.expectRevert(invalid);
        c.proposeOracleConfig(bad);
        bad = _copy(ok);
        bad.price = 10 ether + 1;
        vm.expectRevert(invalid);
        c.proposeOracleConfig(bad);
        bad = _copy(ok);
        bad.panelSize = 4;
        bad.quorum = 3;
        vm.expectRevert(invalid);
        c.proposeOracleConfig(bad);
        bad = _copy(ok);
        bad.panelSize = 101;
        vm.expectRevert(invalid);
        c.proposeOracleConfig(bad);
        bad = _copy(ok);
        bad.quorum = 1;
        vm.expectRevert(invalid);
        c.proposeOracleConfig(bad);
        bad = _copy(ok);
        bad.quorum = 6;
        vm.expectRevert(invalid);
        c.proposeOracleConfig(bad);

        bad = _copy(ok);
        bad.panelSize = 100;
        bad.quorum = 100;
        bad.price = 10 ether;
        c.proposeOracleConfig(bad);
        vm.stopPrank();
        assertEq(c.pendingOracleConfigAt(), block.timestamp + 3 days);
    }

    function test_owner_activationWindowEdgesAndReproposal() public {
        Facts.OracleConfig memory config = c.oracleConfig();
        config.panelSize = 9;
        config.quorum = 7;

        vm.prank(owner);
        vm.expectRevert(Facts.TooEarly.selector);
        c.activateOracleConfig();

        vm.prank(owner);
        c.proposeOracleConfig(config);
        uint256 at = c.pendingOracleConfigAt();
        vm.warp(at - 1);
        vm.prank(owner);
        vm.expectRevert(Facts.TooEarly.selector);
        c.activateOracleConfig();

        // Re-proposing restarts the delay.
        vm.prank(owner);
        c.proposeOracleConfig(config);
        uint256 at2 = c.pendingOracleConfigAt();
        assertEq(at2, block.timestamp + 3 days);
        vm.warp(at);
        vm.prank(owner);
        vm.expectRevert(Facts.TooEarly.selector);
        c.activateOracleConfig();

        vm.warp(at2 + 7 days);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        c.activateOracleConfig();
        vm.prank(owner);
        c.activateOracleConfig();
        assertEq(c.configCount(), 2);
        assertEq(c.oracleConfig().panelSize, 9);
        assertEq(c.oracleConfigAt(0).panelSize, 5, "the first configuration is kept");
        assertEq(c.pendingOracleConfigAt(), 0);
        vm.prank(owner);
        vm.expectRevert(Facts.TooEarly.selector);
        c.activateOracleConfig();
    }

    function test_owner_twoStepTransfer() public {
        address next = makeAddr("next");
        vm.prank(owner);
        c.transferOwnership(next);
        assertEq(c.owner(), owner);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        c.acceptOwnership();
        vm.prank(next);
        c.acceptOwnership();
        assertEq(c.owner(), next);
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        c.setFeeRecipient(alice);
    }

    function test_feeRecipientChangeKeepsAccruedFees() public {
        uint256 id = _create();
        _buy(alice, id, 0, 5 ether);
        uint256 accrued = c.owed(builder);
        assertGt(accrued, 0);
        vm.prank(owner);
        c.setFeeRecipient(carol);
        _buy(bob, id, 1, 5 ether);
        assertEq(c.owed(builder), accrued, "old fees stay with the old recipient");
        assertGt(c.owed(carol), 0);
        vm.prank(builder);
        assertEq(c.withdrawOwed(), accrued);
        vm.prank(builder);
        vm.expectRevert(Facts.NothingToClaim.selector);
        c.withdrawOwed();
    }

    // ---- lifecycle refusals ----------------------------------------------------------------------------------------

    function test_lifecycleRefusals() public {
        vm.expectRevert(Facts.UnknownFact.selector);
        c.openRound(1);
        vm.expectRevert(Facts.UnknownFact.selector);
        c.challenge(0, 1 ether);
        vm.expectRevert(Facts.UnknownFact.selector);
        c.closeRound(7);

        uint256 id = _create();
        vm.expectRevert(Facts.NotSettled.selector);
        c.redeem(id, 2);
        vm.expectRevert(Facts.InvalidChoice.selector);
        c.questionDocument(id, 2, 0, 0);

        uint256 k = _buy(alice, id, 0, 1 ether);
        _judge(id, true);

        vm.startPrank(alice);
        vm.expectRevert(Facts.NotTrading.selector);
        c.sell(id, 0, k, 0);
        vm.expectRevert(Facts.NotTrading.selector);
        c.buyFor(bob, id, 0, 1 ether, 0);
        vm.expectRevert(Facts.NotTrading.selector);
        c.challenge(id, 1 ether);
        vm.stopPrank();
        vm.prank(creator);
        vm.expectRevert(Facts.NotTrading.selector);
        c.closeRound(id);
        vm.prank(alice);
        vm.expectRevert(Facts.NotSeeder.selector);
        c.closeRound(id);
        assertFalse(c.trading(id));

        // A closed round in which the caller holds nothing redeems nothing; an open one cannot be redeemed.
        vm.prank(bob);
        c.openRound(id);
        vm.prank(alice);
        vm.expectRevert(Facts.NotSettled.selector);
        c.redeem(id, 2);
        vm.prank(bob);
        c.closeRound(id);
        vm.prank(alice);
        assertEq(c.redeem(id, 2), 0);

        vm.prank(carol);
        vm.expectRevert(Facts.NothingToClaim.selector);
        c.withdrawOwed();
    }

    function test_buyForWithoutPayerFundsReverts() public {
        uint256 id = _create();
        address poor = makeAddr("poor");
        vm.prank(poor);
        vm.expectRevert();
        c.buyFor(alice, id, 0, 1 ether, 0);
        assertEq(c.sharesOf(id, 1, alice)[0], 0);
        assertEq(c.getRound(id, 1).q[0], 0);
    }

    function test_openRoundRequiresTheSeed() public {
        uint256 id = _create();
        _judge(id, true);
        address poor = makeAddr("poor");
        vm.prank(poor);
        vm.expectRevert();
        c.openRound(id);
        assertEq(c.getFact(id).rounds, 1);
    }

    function test_sellingAnotherRoundsSharesIsImpossible() public {
        uint256 id = _create();
        uint256 k = _buy(alice, id, 0, 2 ether);
        _judge(id, false);
        vm.prank(bob);
        c.openRound(id);
        _buy(carol, id, 0, 2 ether);
        // Alice's losing round-one shares cannot be sold into round two.
        vm.prank(alice);
        vm.expectRevert();
        c.sell(id, 0, k, 0);
        assertEq(c.sharesOf(id, 1, alice)[0], k);
    }

    // ---- fuzzed arithmetic edges -----------------------------------------------------------------------------------

    /// @dev A buy never charges more than `amount`, wastes at most a tiny fraction of it, and its fee splits exactly.
    /// forge-config: default.fuzz.runs = 512
    function testFuzz_buySpendAndFeeSplit(uint64 b, uint256 amount, bool falseSide) public {
        uint256 liquidity = bound(b, 0.1 ether, 100 ether);
        vm.prank(creator);
        uint256 id = c.createFact(TOPIC, CLAIM, RULES, liquidity);
        amount = bound(amount, 1e15, liquidity * 15 > 900 ether ? 900 ether : liquidity * 15);
        uint8 side = falseSide ? 1 : 0;
        (uint256 quoted, uint256 cost, uint256 fee) = c.quoteBuy(id, side, amount);
        uint256 before = imd.balanceOf(alice);
        uint256 seederBefore = c.owed(creator);
        uint256 builderBefore = c.owed(builder);
        uint256 deadBefore = imd.balanceOf(DEAD);
        uint256 k = _buy(alice, id, side, amount);
        assertEq(k, quoted);
        uint256 spent = before - imd.balanceOf(alice);
        assertEq(spent, cost + fee);
        assertLe(spent, amount);
        assertEq(fee, (cost * 200 + 9_999) / 10_000, "fee is 2% rounded up");
        uint256 toSeeder = c.owed(creator) - seederBefore;
        uint256 burned = imd.balanceOf(DEAD) - deadBefore;
        uint256 toBuilder = c.owed(builder) - builderBefore;
        assertEq(toSeeder + burned + toBuilder, fee, "the fee splits without remainder");
        assertEq(toSeeder, fee / 2);
        assertEq(burned, fee * 67 / 200);
        assertGt(k, cost, "a share costs less than 1 IMD");
        Facts.Round memory r = c.getRound(id, 1);
        assertEq(r.makerBalance, r.seed + cost);
    }

    /// @dev Buying and selling straight back never returns more than was paid, and selling never pays more than
    ///      one IMD per share.
    /// forge-config: default.fuzz.runs = 512
    function testFuzz_roundTripNeverProfits(uint64 b, uint256 pre, uint256 amount, bool falseSide) public {
        uint256 liquidity = bound(b, 0.1 ether, 100 ether);
        vm.prank(creator);
        uint256 id = c.createFact(TOPIC, CLAIM, RULES, liquidity);
        uint8 side = falseSide ? 1 : 0;
        // Move the price first with another trader.
        vm.prank(bob);
        uint256 cap = liquidity * 10 > 400 ether ? 400 ether : liquidity * 10;
        try c.buy(id, 1 - side, bound(pre, 1e15, cap), 0) {} catch {}
        amount = bound(amount, 1e15, cap);
        uint256 before = imd.balanceOf(alice);
        vm.prank(alice);
        try c.buy(id, side, amount, 0) returns (uint256 k) {
            vm.prank(alice);
            uint256 proceeds = c.sell(id, side, k, 0);
            assertLe(proceeds, k);
            assertLt(imd.balanceOf(alice), before, "a round trip loses at least the fees");
        } catch (bytes memory err) {
            bytes4 sel = bytes4(err);
            assertTrue(
                sel == Facts.PriceLimit.selector || sel == Facts.TradeTooSmall.selector
                    || sel == Facts.TradeTooLarge.selector,
                "unexpected buy revert"
            );
        }
        Facts.Round memory r = c.getRound(id, 1);
        assertGe(r.makerBalance, uint256(r.q[0] > r.q[1] ? r.q[0] : r.q[1]));
    }

    /// @dev The seeder never loses more than the seed: residual plus fees earned is at least zero by construction, and
    ///      settlement never reverts (the maker covers the winning side) whatever the trades and the verdict.
    /// forge-config: default.fuzz.runs = 256
    function testFuzz_settlementAlwaysCoversTheWinners(uint256 seed, bool verdict, uint64 b) public {
        uint256 liquidity = bound(b, 0.1 ether, 100 ether);
        vm.prank(creator);
        uint256 id = c.createFact(TOPIC, CLAIM, RULES, liquidity);
        address[3] memory traders = [alice, bob, carol];
        uint256 paidIn;
        for (uint256 i; i < 12; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            address who = traders[r % 3];
            uint8 side = uint8((r >> 8) % 2);
            uint256 before = imd.balanceOf(who);
            vm.prank(who);
            try c.buy(id, side, bound(r >> 16, 1e15, 25 * liquidity), 0) {
                paidIn += before - imd.balanceOf(who);
            } catch {}
        }
        Facts.Round memory pre = c.getRound(id, 1);
        imd.mint(carol, 1 ether);
        uint8 winner = verdict ? 0 : 1;
        uint256 seederOwedBefore = c.owed(creator);
        _judge(id, verdict);
        Facts.Round memory post = c.getRound(id, 1);
        assertEq(post.makerBalance, uint256(pre.q[winner]));
        assertEq(c.owed(creator) - seederOwedBefore, pre.makerBalance - uint256(pre.q[winner]));
        // Every IMD traders paid in, less the fees, is in the maker: the seeder's loss is bounded by the seed.
        assertGe(pre.makerBalance, pre.seed);
        assertLe(pre.makerBalance - pre.seed, paidIn);
    }

    // ---- gas ---------------------------------------------------------------------------------------------------

    function test_callbackWithErc1271SignerFitsUnder200k() public {
        MockSignerRegistry registry = new MockSignerRegistry();
        registry.set(signer, true);
        _rotate(
            Facts.OracleConfig({
                intake: IIntake(address(intake)),
                signer: address(registry),
                price: 0.5 ether,
                panelSize: 5,
                quorum: 4,
                action: bytes32("oracle.request@oracle-1")
            })
        );
        uint256 id = _create();
        _buy(alice, id, 0, 3 ether);
        _buy(bob, id, 1, 1 ether);
        AskRef memory ref = _challenge(carol, id);
        IOracleAttestation.Attestation memory a = _attestation(id, ref, true);
        bytes memory sig = _sign(a, signerKey);
        vm.prank(address(intake));
        uint256 g = gasleft();
        c.onOracleResult(ref.requestId, a, sig);
        assertLt(g - gasleft(), 180_000);
    }

    function test_failureCallbackFitsUnder200k() public {
        uint256 id = _create();
        AskRef memory ref = _challenge(carol, id);
        vm.prank(address(intake));
        uint256 g = gasleft();
        c.onFailure(ref.requestId, 1, "body_refused", 0, 0, "");
        assertLt(g - gasleft(), 60_000);
    }

    // ---- helpers ---------------------------------------------------------------------------------------------------

    /// @dev Withdraws everything owed and checks that only dust beyond the unredeemed winners is left.
    // ---- closeRound with shares outstanding (implementation since d262ee8; see .imd-findings.json) ---------------

    /// @dev One-sided trading: the maker holds more than the shares held, the seeder takes the surplus back and every
    ///      holder redeems 1 IMD per share, whatever side.
    function test_closeWithSharesHeldPaysEveryHolderInFull() public {
        uint256 id = _create();
        uint256 k = _buy(alice, id, 0, 3 ether);
        Facts.Round memory pre = c.getRound(id, 1);
        assertGt(pre.makerBalance, k);
        uint256 before = imd.balanceOf(creator);
        vm.prank(creator);
        uint256 refund = c.closeRound(id);
        assertEq(refund, pre.makerBalance - k);
        assertEq(imd.balanceOf(creator) - before, refund);
        assertEq(c.getRound(id, 1).makerBalance, k);
        assertEq(c.redeemable(id, 1, alice), k);
        vm.prank(alice);
        assertEq(c.redeem(id, 1), k);
        vm.prank(alice);
        assertEq(c.redeem(id, 1), 0, "a second redemption pays nothing");
        // A closed round takes no trade, no challenge and no second close.
        vm.prank(bob);
        vm.expectRevert(Facts.NotTrading.selector);
        c.buy(id, 1, 1 ether, 0);
        vm.prank(carol);
        vm.expectRevert(Facts.NotTrading.selector);
        c.challenge(id, 10 ether);
        vm.prank(creator);
        vm.expectRevert(Facts.NotTrading.selector);
        c.closeRound(id);
        _drainAll();
    }

    /// @dev Both sides bought: shares held exceed the maker, so the seeder pays in the shortfall (losing more than the
    ///      seed) and both sides redeem 1 IMD per share. A seeder without the shortfall cannot close.
    function test_closeWithBothSidesHeldMakesTheSeederPayTheShortfall() public {
        uint256 id = _create();
        uint256 k0 = _buy(alice, id, 0, 40 ether);
        uint256 k1 = _buy(bob, id, 1, 40 ether);
        Facts.Round memory pre = c.getRound(id, 1);
        assertGt(k0 + k1, pre.makerBalance, "both sides held exceed the maker");
        uint256 shortfall = k0 + k1 - pre.makerBalance;

        // A seeder who cannot pay the shortfall cannot close; nothing changes.
        vm.prank(creator);
        imd.approve(address(c), shortfall - 1);
        vm.prank(creator);
        vm.expectRevert();
        c.closeRound(id);
        assertTrue(c.trading(id));

        vm.prank(creator);
        imd.approve(address(c), type(uint256).max);
        uint256 before = imd.balanceOf(creator);
        vm.prank(creator);
        assertEq(c.closeRound(id), 0);
        assertEq(before - imd.balanceOf(creator), shortfall);
        assertGt(shortfall, pre.seed, "the seeder loses more than the seed");
        vm.prank(alice);
        assertEq(c.redeem(id, 1), k0);
        vm.prank(bob);
        assertEq(c.redeem(id, 1), k1);
        _drainAll();
    }

    function _drainAll() internal {
        address[5] memory who = [creator, alice, bob, carol, builder];
        for (uint256 i; i < who.length; ++i) {
            if (c.owed(who[i]) > 0) {
                vm.prank(who[i]);
                c.withdrawOwed();
            }
        }
        uint256 liabilities;
        for (uint256 id = 1; id <= c.factCount(); ++id) {
            for (uint32 r = 1; r <= c.getFact(id).rounds; ++r) {
                liabilities += c.getRound(id, r).makerBalance;
            }
        }
        uint256 held = imd.balanceOf(address(c));
        assertGe(held, liabilities, "solvent");
        assertLe(held - liabilities, 1e9, "only rounding dust is left");
    }

    function _rotate(Facts.OracleConfig memory config) internal {
        vm.prank(owner);
        c.proposeOracleConfig(config);
        vm.warp(block.timestamp + 3 days);
        vm.prank(owner);
        c.activateOracleConfig();
    }

    function _copy(Facts.OracleConfig memory x) internal pure returns (Facts.OracleConfig memory y) {
        y = Facts.OracleConfig(x.intake, x.signer, x.price, x.panelSize, x.quorum, x.action);
    }

    function _structHash(IOracleAttestation.Attestation memory a) internal pure returns (bytes32) {
        bytes32 typehash = keccak256(
            "OracleAttestation(bytes32 requestId,uint256 chainId,bytes32 questionHash,uint8 answerType,bytes answer,"
            "uint256 figure,uint64 fromBlock,uint64 toBlock,bytes32 blockHash,bytes32 panelJobId,uint16 panelSize,"
            "uint16 quorum,uint16 agreed,uint64 issuedAt,uint64 expiresAt)"
        );
        return keccak256(
            bytes.concat(
                abi.encode(
                    typehash,
                    a.requestId,
                    a.chainId,
                    a.questionHash,
                    a.answerType,
                    keccak256(a.answer),
                    a.figure,
                    a.fromBlock
                ),
                abi.encode(
                    a.toBlock, a.blockHash, a.panelJobId, a.panelSize, a.quorum, a.agreed, a.issuedAt, a.expiresAt
                )
            )
        );
    }

    function _typed(bytes32 structHash, uint256 chainId, address verifying) internal pure returns (bytes32) {
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("IdentityMD Oracle"),
                keccak256("2"),
                chainId,
                verifying
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }
}
