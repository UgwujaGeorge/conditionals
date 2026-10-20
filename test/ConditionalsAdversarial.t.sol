// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Conditionals} from "../src/Conditionals.sol";
import {IIntake} from "../src/interfaces/IIntake.sol";
import {IOracleAttestation} from "../src/interfaces/IOracleAttestation.sol";
import {Fixture} from "./utils/Fixture.sol";
import {MockIntake} from "./utils/Mocks.sol";

/// @dev Deploys Conditionals in one call with the factory as msg.sender, as the launch does.
contract LaunchFactory {
    function launch(address owner_, IERC20 imd_, IIntake intake_, address signer_, address fee_)
        external
        returns (Conditionals)
    {
        return new Conditionals(owner_, imd_, intake_, signer_, fee_);
    }
}

/// @dev Inputs the happy-path suite does not exercise: boundaries, wrong callers, replays across domains, the owner's
///      reach, and calls that must change nothing.
contract ConditionalsAdversarialTest is Fixture {
    uint256 internal constant ATTACKER_KEY = 0xBAD;

    // ---------------------------------------------------------------------------------------------------------------
    // Deployment as the launch does it
    // ---------------------------------------------------------------------------------------------------------------

    function test_launchConstructorOnAnEmptyRobinhoodChain() public {
        vm.chainId(4663);
        address imdAddr = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
        address intakeAddr = 0xa43e6F75ee006411F79Ac1C84120606C2330DE82;
        address signerAddr = 0x5598Aa9146215Bc13eb26f2c692Ad1461Fd32982;
        address feeAddr = 0x63BCf2d1483c7628d7D53704ff9c8199Dc28d907;
        // The launch checks run constructors where none of these has code: the constructor must not call them.
        assertEq(imdAddr.code.length + intakeAddr.code.length + signerAddr.code.length, 0);

        LaunchFactory factory = new LaunchFactory();
        Conditionals d = factory.launch(owner, IERC20(imdAddr), IIntake(intakeAddr), signerAddr, feeAddr);

        assertEq(d.owner(), owner, "owner is the named owner, never the factory");
        assertTrue(d.owner() != address(factory));
        assertEq(d.pendingOwner(), address(0));
        assertEq(address(d.imd()), imdAddr);
        assertEq(d.feeRecipient(), feeAddr);
        (IIntake i, address s, uint128 price, uint16 panel, uint16 quorum, bytes32 action) = d.oracleConfig();
        assertEq(address(i), intakeAddr);
        assertEq(s, signerAddr);
        assertEq(price, 0.5 ether);
        assertEq(panel, 5);
        assertEq(quorum, 4);
        assertEq(action, 0x6f7261636c652e72657175657374406f7261636c652d31000000000000000000);
        (,,, uint256 chainId, address verifying,,) = d.eip712Domain();
        assertEq(chainId, 4663);
        assertEq(verifying, address(d));
        assertEq(d.BURN_ADDRESS(), 0x000000000000000000000000000000000000dEaD);
        assertEq(d.marketCount(), 0);
    }

    function test_constructorRefusesZeroOwnerIntakeOrSigner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new Conditionals(address(0), IERC20(address(imd)), IIntake(address(intake)), signer, builder);
        vm.expectRevert(Conditionals.ZeroAddress.selector);
        new Conditionals(owner, IERC20(address(imd)), IIntake(address(0)), signer, builder);
        vm.expectRevert(Conditionals.ZeroAddress.selector);
        new Conditionals(owner, IERC20(address(imd)), IIntake(address(intake)), address(0), builder);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Time boundaries
    // ---------------------------------------------------------------------------------------------------------------

    function test_stakeClosesExactlyAtCloseTime() public {
        uint256 id = _create();
        vm.warp(closeTime - 1);
        _stake(alice, id, 0, 0, 1 ether);
        vm.warp(closeTime);
        vm.prank(alice);
        vm.expectRevert(Conditionals.BettingClosed.selector);
        c.stake(id, 0, 0, 1 ether);
    }

    function test_resolutionOpensExactlyAtResolveTimeAndEndsAtVoidAfter() public {
        uint256 id = _create();
        vm.warp(resolveTime - 1);
        assertFalse(c.askable(id, 0));
        vm.expectRevert(Conditionals.TooEarly.selector);
        c.requestResolution(id);

        uint64 voidAfter = c.getMarket(id).voidAfter;
        assertEq(voidAfter, resolveTime + 30 days);
        vm.warp(voidAfter + 1);
        assertFalse(c.askable(id, 0));
        vm.expectRevert(Conditionals.MarketNotOpen.selector);
        c.requestResolution(id);
    }

    function test_voidOpensOnlyAfterVoidAfter() public {
        uint256 id = _create();
        _stake(alice, id, 0, 0, 3 ether);
        uint64 voidAfter = c.getMarket(id).voidAfter;
        vm.warp(voidAfter);
        assertFalse(c.voidable(id));
        vm.expectRevert(Conditionals.NotVoidable.selector);
        c.voidMarket(id);
        vm.warp(voidAfter + 1);
        uint256 before = imd.balanceOf(creator);
        c.voidMarket(id);
        // Never asked: the whole 1 IMD budget goes back to the creator.
        assertEq(imd.balanceOf(creator) - before, 1 ether);
        assertEq(_claim(alice, id), 3 ether);
    }

    /// @dev An ask sent in the last second of the period holds off a void for RETRY_DELAY, and no longer.
    function test_lastSecondAskDelaysVoidByOneDayAtMost() public {
        uint256 id = _create();
        _stake(alice, id, 0, 0, 3 ether);
        uint64 voidAfter = c.getMarket(id).voidAfter;
        vm.warp(voidAfter);
        c.requestResolution(id);
        vm.warp(voidAfter + 1 days - 1);
        assertFalse(c.voidable(id));
        vm.warp(voidAfter + 1 days);
        assertTrue(c.voidable(id));
        c.voidMarket(id);
        assertEq(uint8(c.getMarket(id).status), uint8(Conditionals.Status.Voided));
    }

    function test_expiryBoundary() public {
        uint256 id = _create();
        AskRef[] memory refs = _request(id);
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], true);
        a.expiresAt = uint64(block.timestamp);
        assertTrue(_deliver(refs[0].requestId, a, _sign(a, signerKey)), "valid through expiresAt");

        a = _attestation(id, refs[1], true);
        a.expiresAt = uint64(block.timestamp - 1);
        assertFalse(_deliver(refs[1].requestId, a, _sign(a, signerKey)));
        assertEq(c.getMarket(id).openAsks[1], 1, "a refused answer leaves the ask pending");
    }

    // ---------------------------------------------------------------------------------------------------------------
    // The panel
    // ---------------------------------------------------------------------------------------------------------------

    function test_panelChecks() public {
        uint256 id = _create();
        AskRef[] memory refs = _request(id);
        bytes32 rid = refs[0].requestId;

        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], true);
        a.agreed = 6; // more agreed than seats
        assertFalse(_raw(rid, a, _sign(a, signerKey)));

        a = _attestation(id, refs[0], true);
        a.quorum = 3; // below the market's quorum, even with everyone agreeing
        a.agreed = 5;
        assertFalse(_raw(rid, a, _sign(a, signerKey)));

        a = _attestation(id, refs[0], true);
        a.panelSize = 4;
        a.quorum = 4;
        a.agreed = 4;
        assertFalse(_raw(rid, a, _sign(a, signerKey)));

        a = _attestation(id, refs[0], true);
        a.agreed = 3; // below quorum
        assertFalse(_raw(rid, a, _sign(a, signerKey)));

        // A larger panel with exactly its quorum agreeing is enough.
        a = _attestation(id, refs[0], false);
        a.panelSize = 30;
        a.quorum = 20;
        a.agreed = 20;
        assertTrue(_raw(rid, a, _sign(a, signerKey)));
        assertEq(c.getMarket(id).answers[0], 2);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Replays across domains and requests
    // ---------------------------------------------------------------------------------------------------------------

    /// @dev Two deployments share the signer and the Intake. An answer signed for one is refused by the other even when
    ///      every field, the question hash included, is the other's.
    function test_signatureForAnotherDeploymentIsRefused() public {
        Conditionals c2 = new Conditionals(owner, IERC20(address(imd)), IIntake(address(intake)), signer, builder);
        vm.prank(creator);
        imd.approve(address(c2), type(uint256).max);
        vm.prank(creator);
        uint256 id2 = c2.createMarket(CONDITION, OUTCOME, RULES, closeTime, resolveTime, 1 ether);
        vm.warp(resolveTime);
        uint256 before = intake.count();
        c2.requestResolution(id2);
        bytes32 rid = intake.requestIds(before);
        uint256 windowBlock = block.number - 10;

        IOracleAttestation.Attestation memory a;
        a.requestId = bytes32(uint256(1));
        a.chainId = 1;
        a.questionHash = keccak256(bytes(c2.questionDocument(id2, 0, windowBlock)));
        a.answer = abi.encode(true);
        a.fromBlock = uint64(windowBlock);
        a.toBlock = uint64(windowBlock);
        a.panelSize = 5;
        a.quorum = 4;
        a.agreed = 4;
        a.issuedAt = uint64(block.timestamp);
        a.expiresAt = uint64(block.timestamp + 1 days);

        // _digest is the fixture deployment's domain, not c2's.
        assertFalse(_deliver(rid, a, _sign(a, signerKey)));
        assertEq(c2.getMarket(id2).answers[0], 0);
        // Signed in c2's own domain it is accepted, so the refusal above was the domain alone.
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerKey, c2.attestationDigest(a));
        assertTrue(intake.deliverRaw(address(c2), _cb(rid, a, abi.encodePacked(r, s, v))));
        assertEq(c2.getMarket(id2).answers[0], 1);
    }

    /// @dev A signature made while the contract was on one chain does not verify on another.
    function test_signatureForAnotherChainIsRefused() public {
        uint256 id = _create();
        AskRef[] memory refs = _request(id);
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], true);
        bytes memory sig = _sign(a, signerKey);
        assertEq(block.chainid, 31_337);
        vm.chainId(4663);
        assertFalse(_raw(refs[0].requestId, a, sig));
        vm.chainId(31_337);
        assertTrue(_raw(refs[0].requestId, a, sig));
    }

    /// @dev The condition's answer cannot settle the outcome question of the same market, nor the reverse.
    function test_answerToTheOtherQuestionOfTheSameMarketIsRefused() public {
        uint256 id = _create();
        AskRef[] memory refs = _request(id);
        IOracleAttestation.Attestation memory forCondition = _attestation(id, refs[0], true);
        IOracleAttestation.Attestation memory forOutcome = _attestation(id, refs[1], true);
        assertFalse(_raw(refs[1].requestId, forCondition, _sign(forCondition, signerKey)));
        assertFalse(_raw(refs[0].requestId, forOutcome, _sign(forOutcome, signerKey)));
        assertEq(c.getMarket(id).answers[0], 0);
        assertEq(c.getMarket(id).answers[1], 0);
    }

    /// @dev The answer to the first ask of a question does not fit a retry over a later window.
    function test_answerForAnOlderWindowDoesNotFitTheRetry() public {
        uint256 id = _create();
        AskRef[] memory refs = _request(id);
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 7200);
        AskRef[] memory retry = _request(id);
        IOracleAttestation.Attestation memory old = _attestation(id, refs[0], true);
        assertFalse(_raw(retry[0].requestId, old, _sign(old, signerKey)));
        assertTrue(_raw(refs[0].requestId, old, _sign(old, signerKey)));
    }

    /// @dev Calldata the callback cannot decode is refused and leaves the ask answerable.
    function test_malformedCallbackLeavesTheAskPending() public {
        uint256 id = _create();
        AskRef[] memory refs = _request(id);
        assertFalse(intake.deliverRaw(address(c), abi.encodeWithSelector(c.onOracleResult.selector, refs[0].requestId)));
        assertFalse(intake.deliverRaw(address(c), abi.encodePacked(c.onOracleResult.selector, refs[0].requestId)));
        assertEq(c.getMarket(id).openAsks[0], 1);
        assertTrue(_answer(id, refs[0], true));
    }

    /// @dev A second Intake (an attacker's contract) has its own keys: the same request id from it is unknown.
    function test_sameRequestIdFromAnotherIntakeIsUnknown() public {
        uint256 id = _create();
        AskRef[] memory refs = _request(id);
        MockIntake other = new MockIntake();
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], true);
        assertFalse(other.deliverRaw(address(c), _cb(refs[0].requestId, a, _sign(a, signerKey))));
        assertFalse(
            other.deliverRaw(
                address(c),
                abi.encodeCall(c.onFailure, (refs[0].requestId, uint8(2), bytes32("disagreed"), 0, 0, bytes("")))
            )
        );
        assertEq(c.getMarket(id).openAsks[0], 1);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Failures are not signals
    // ---------------------------------------------------------------------------------------------------------------

    function test_failureMovesNoValueAndClearsOnlyItsAsk() public {
        uint256 id = _create();
        _stake(alice, id, 0, 0, 5 ether);
        _stake(bob, id, 0, 1, 5 ether);
        AskRef[] memory refs = _request(id);
        uint256 held = imd.balanceOf(address(c));
        uint256 aliceBefore = imd.balanceOf(alice);

        assertTrue(intake.fail(refs[0].requestId, 1, "body_refused"));
        assertEq(imd.balanceOf(address(c)), held);
        assertEq(imd.balanceOf(alice), aliceBefore);
        Conditionals.Market memory m = c.getMarket(id);
        assertEq(m.openAsks[0], 0);
        assertEq(m.openAsks[1], 1, "the other question's ask is untouched");
        assertEq(m.answers[0], 0);
        assertEq(uint8(m.status), uint8(Conditionals.Status.Open));
        assertFalse(c.settleable(id));
        assertEq(c.claimable(id, alice), 0);

        // Once cleared, a second failure (or a late answer) for it is unknown.
        bytes memory again = abi.encodeCall(c.onFailure, (refs[0].requestId, uint8(2), bytes32("failed"), 0, 0, ""));
        assertFalse(intake.deliverRaw(address(c), again));
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], true);
        assertFalse(_raw(refs[0].requestId, a, _sign(a, signerKey)));
    }

    function test_failureAfterAnAnswerIsUnknown() public {
        uint256 id = _create();
        AskRef[] memory refs = _request(id);
        assertTrue(_answer(id, refs[0], true));
        bytes memory f = abi.encodeCall(c.onFailure, (refs[0].requestId, uint8(2), bytes32("failed"), 0, 0, ""));
        assertFalse(intake.deliverRaw(address(c), f));
        assertEq(c.getMarket(id).answers[0], 1);
    }

    function test_failureFitsTheIntakeGasLimit() public {
        uint256 id = _create();
        AskRef[] memory refs = _request(id);
        bytes memory f = abi.encodeCall(c.onFailure, (refs[0].requestId, uint8(2), bytes32("disagreed"), 3, 5, ""));
        vm.prank(address(intake));
        uint256 g = gasleft();
        (bool ok,) = address(c).call(f);
        assertTrue(ok);
        assertLt(g - gasleft(), 100_000);
    }

    function test_retryWithoutPaymentRevertsAndChangesNothing() public {
        uint256 id = _create();
        AskRef[] memory refs = _request(id);
        intake.fail(refs[0].requestId, 2, "disagreed");
        address broke = makeAddr("broke");
        uint256 n = intake.count();
        vm.prank(broke);
        vm.expectRevert();
        c.requestResolution(id);
        assertEq(intake.count(), n);
        assertTrue(c.askable(id, 0));
        assertEq(c.getMarket(id).openAsks[0], 0);
        assertEq(imd.allowance(address(c), address(intake)), 0);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Finished markets stay finished
    // ---------------------------------------------------------------------------------------------------------------

    function test_settledMarketCannotReopenOrBeVoided() public {
        uint256 id = _create();
        _stake(alice, id, 0, 0, 2 ether);
        _stake(bob, id, 0, 1, 2 ether);
        _resolve(id, true, true);
        c.settle(id);

        vm.expectRevert(Conditionals.NotSettleable.selector);
        c.settle(id);
        vm.warp(c.getMarket(id).voidAfter + 2 days);
        assertFalse(c.voidable(id));
        vm.expectRevert(Conditionals.NotVoidable.selector);
        c.voidMarket(id);
        vm.expectRevert(Conditionals.MarketNotOpen.selector);
        c.requestResolution(id);
        vm.prank(carol);
        vm.expectRevert(Conditionals.MarketNotOpen.selector);
        c.stake(id, 0, 0, 1 ether);
        // Losers have nothing to claim.
        vm.prank(bob);
        vm.expectRevert(Conditionals.NothingToClaim.selector);
        c.claim(id);
        assertEq(uint8(c.getMarket(id).status), uint8(Conditionals.Status.Settled));
    }

    function test_voidedMarketCannotBeSettledOrVoidedAgain() public {
        uint256 id = _create();
        _stake(alice, id, 1, 0, 2 ether);
        AskRef[] memory refs = _request(id);
        assertTrue(_answer(id, refs[0], false));
        vm.warp(c.getMarket(id).voidAfter + 1 days);
        c.voidMarket(id);
        // The late outcome answer is consumed but changes nothing.
        assertTrue(_answer(id, refs[1], true));
        assertEq(c.getMarket(id).answers[1], 0);
        assertFalse(c.settleable(id));
        vm.expectRevert(Conditionals.NotSettleable.selector);
        c.settle(id);
        vm.expectRevert(Conditionals.NotVoidable.selector);
        c.voidMarket(id);
        assertEq(_claim(alice, id), 2 ether);
    }

    function test_unknownMarketIds() public {
        _create();
        for (uint256 i; i < 2; ++i) {
            uint256 id = i == 0 ? 0 : 2;
            vm.expectRevert(Conditionals.UnknownMarket.selector);
            c.stake(id, 0, 0, 1 ether);
            vm.expectRevert(Conditionals.UnknownMarket.selector);
            c.requestResolution(id);
            vm.expectRevert(Conditionals.UnknownMarket.selector);
            c.settle(id);
            vm.expectRevert(Conditionals.UnknownMarket.selector);
            c.voidMarket(id);
            vm.expectRevert(Conditionals.UnknownMarket.selector);
            c.claim(id);
            assertFalse(c.askable(id, 0));
            assertFalse(c.settleable(id));
            assertFalse(c.voidable(id));
            assertEq(c.claimable(id, alice), 0);
        }
        assertFalse(c.askable(1, 2));
    }

    // ---------------------------------------------------------------------------------------------------------------
    // The owner's reach
    // ---------------------------------------------------------------------------------------------------------------

    function test_ownerOnlyFunctionsRefuseEveryoneElse() public {
        Conditionals.OracleConfig memory cfg = _config();
        address[3] memory others = [alice, creator, builder];
        for (uint256 i; i < others.length; ++i) {
            vm.startPrank(others[i]);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, others[i]));
            c.proposeOracleConfig(cfg);
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, others[i]));
            c.activateOracleConfig();
            vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, others[i]));
            c.setFeeRecipient(others[i]);
            vm.stopPrank();
        }
        vm.prank(owner);
        vm.expectRevert(Conditionals.TooEarly.selector);
        c.activateOracleConfig();
    }

    /// @dev The owner rotates in its own signer and Intake. The open market keeps its configuration: the owner's
    ///      signature cannot answer it, its own Intake cannot call it, and the honest answer still settles it.
    function test_ownerRotationCannotReachAnOpenMarket() public {
        uint256 id = _create();
        _stake(alice, id, 0, 0, 10 ether);
        _stake(bob, id, 0, 1, 10 ether);
        Conditionals.Market memory before = c.getMarket(id);

        MockIntake evil = new MockIntake();
        Conditionals.OracleConfig memory cfg = Conditionals.OracleConfig({
            intake: IIntake(address(evil)),
            signer: vm.addr(ATTACKER_KEY),
            price: 0.5 ether,
            panelSize: 5,
            quorum: 2,
            action: bytes32("oracle.request@oracle-1")
        });
        vm.startPrank(owner);
        c.proposeOracleConfig(cfg);
        vm.warp(block.timestamp + 3 days - 1);
        vm.expectRevert(Conditionals.TooEarly.selector);
        c.activateOracleConfig();
        vm.warp(block.timestamp + 1);
        c.activateOracleConfig();
        vm.stopPrank();

        Conditionals.Market memory m = c.getMarket(id);
        assertEq(address(m.oracle.intake), address(before.oracle.intake));
        assertEq(m.oracle.signer, before.oracle.signer);
        assertEq(m.oracle.quorum, 4);

        AskRef[] memory refs = _request(id);
        assertEq(evil.count(), 0, "the open market still asks its own Intake");
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], false);
        assertFalse(_raw(refs[0].requestId, a, _sign(a, ATTACKER_KEY)));
        assertFalse(evil.deliverRaw(address(c), _cb(refs[0].requestId, a, _sign(a, ATTACKER_KEY))));
        assertEq(c.getMarket(id).answers[0], 0);

        _answer(id, refs[0], true);
        _answer(id, refs[1], true);
        assertEq(_claim(alice, id), 20 ether * 97 / 100);
    }

    /// @dev The fee recipient is read at settlement, so a change reaches markets already open. The brief lets the
    ///      owner set it; this pins where the 1% goes.
    function test_feeRecipientIsReadAtSettlement() public {
        uint256 id = _create();
        _stake(alice, id, 0, 0, 10 ether);
        _stake(bob, id, 0, 1, 10 ether);
        address next = makeAddr("next");
        vm.prank(owner);
        c.setFeeRecipient(next);
        _resolve(id, true, false);
        c.settle(id);
        assertEq(imd.balanceOf(next), 0.2 ether);
        assertEq(imd.balanceOf(builder), 0);
        assertEq(imd.balanceOf(DEAD), 0.4 ether);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Settlement arithmetic at its edges
    // ---------------------------------------------------------------------------------------------------------------

    /// @dev 3% of a 101 IMD pot (3.03 IMD) is more than the 1 IMD the losing side staked, so the fee is capped at the
    ///      losing pool, split 2:1 between the burn and the fee recipient, and the winner gets back exactly its stake.
    function test_lopsidedWinnersAreMadeWholeByTheFeeCap() public {
        uint256 id = _create();
        _stake(alice, id, 0, 0, 100 ether);
        _stake(bob, id, 0, 1, 1 ether);
        _resolve(id, true, true);
        uint256 got = _claim(alice, id);
        assertEq(got, 100 ether);
        uint256 burned = uint256(1 ether) * 200 / 300;
        assertEq(imd.balanceOf(DEAD), burned);
        assertEq(imd.balanceOf(builder), 1 ether - burned);
        assertEq(imd.balanceOf(address(c)), 0);
        vm.prank(bob);
        vm.expectRevert(Conditionals.NothingToClaim.selector);
        c.claim(id);
    }

    /// @dev Exactly at the cap (losing = 3% of the pot) the uncapped split applies; below it the cap does.
    function test_feeCapBoundary() public {
        // pot = 100 IMD, losing = 3 IMD: 3% of the pot equals the losing pool, so the uncapped split applies.
        uint256 id = _create();
        uint256 id2 = _create();
        _stake(alice, id, 0, 0, 97 ether);
        _stake(bob, id, 0, 1, 3 ether);
        _stake(alice, id2, 0, 0, 97 ether);
        _stake(bob, id2, 0, 1, 2 ether);
        _resolve(id, true, true);
        assertEq(_claim(alice, id), 97 ether);
        assertEq(imd.balanceOf(DEAD), 2 ether);
        assertEq(imd.balanceOf(builder), 1 ether);

        // pot = 99 IMD, losing = 2 IMD < 2.97 IMD: the cap applies, all 2 IMD go in fees and the winner nets its stake.
        _resolve(id2, true, true);
        uint256 burned2 = uint256(2 ether) * 200 / 300;
        assertEq(_claim(alice, id2), 97 ether);
        assertEq(imd.balanceOf(DEAD), 2 ether + burned2);
        assertEq(imd.balanceOf(builder), 1 ether + (2 ether - burned2));
    }

    /// @dev The smallest stakes on both sides: fees round down, winners split what is left, nothing is created.
    function test_minimumStakesSettle() public {
        uint256 id = _create();
        uint256 minStake = c.MIN_STAKE();
        _stake(alice, id, 0, 0, minStake);
        _stake(bob, id, 0, 1, minStake);
        _stake(carol, id, 0, 0, minStake);
        _resolve(id, true, true);
        c.settle(id);
        uint256 pot = 3 * minStake;
        uint256 a = _claim(alice, id);
        uint256 b = _claim(carol, id);
        assertEq(a, b);
        assertLe(a + b + pot * 2 / 100 + pot / 100, pot);
        assertGe(a + b + pot * 2 / 100 + pot / 100 + 1, pot);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_winnersSplitTheNetPotWithBoundedDust(uint96 w1, uint96 w2, uint96 w3, uint96 l, bool outcome)
        public
    {
        uint256 minStake = c.MIN_STAKE();
        uint256[3] memory win = [bound(w1, minStake, 1e27), bound(w2, minStake, 1e27), bound(w3, minStake, 1e27)];
        uint256 lose = bound(l, minStake, 1e27);
        uint8 winSide = outcome ? 0 : 1;
        uint256 id = _create();
        address[3] memory winners = [alice, bob, carol];
        for (uint256 i; i < 3; ++i) {
            imd.mint(winners[i], win[i]);
            _stake(winners[i], id, 1, winSide, win[i]);
        }
        imd.mint(dave, lose);
        _stake(dave, id, 1, 1 - winSide, lose);
        _resolve(id, false, outcome);
        c.settle(id);

        uint256 pot = win[0] + win[1] + win[2] + lose;
        uint256 burned = pot * 200 / 10_000;
        uint256 fee = pot * 100 / 10_000;
        if (burned + fee > lose) {
            // The fee is capped at the losing pool, split 2:1.
            burned = lose * 200 / 300;
            fee = lose - burned;
        }
        assertLe(burned + fee, lose, "the fee never exceeds what the losing side staked");
        assertLe(burned + fee, pot * 3 / 100, "the fee never exceeds 3% of the pot");
        assertEq(imd.balanceOf(DEAD), burned);
        assertEq(imd.balanceOf(builder), fee);
        uint256 paid;
        for (uint256 i; i < 3; ++i) {
            uint256 got = _claim(winners[i], id);
            assertEq(got, win[i] * (pot - burned - fee) / (win[0] + win[1] + win[2]));
            assertGe(got, win[i], "a winner never nets less than it staked");
            paid += got;
        }
        assertLe(paid, pot - burned - fee);
        assertLt(pot - burned - fee - paid, 3, "dust is at most one wei per winner");
        assertEq(imd.balanceOf(address(c)), pot - burned - fee - paid);
        vm.prank(dave);
        vm.expectRevert(Conditionals.NothingToClaim.selector);
        c.claim(id);
    }

    // ---------------------------------------------------------------------------------------------------------------

    function _cb(bytes32 rid, IOracleAttestation.Attestation memory a, bytes memory sig)
        internal
        view
        returns (bytes memory)
    {
        return abi.encodeWithSelector(c.onOracleResult.selector, rid, a, sig);
    }

    /// @dev Delivers through the Intake's address under its 200,000 gas stipend without completing the mock's record.
    function _raw(bytes32 rid, IOracleAttestation.Attestation memory a, bytes memory sig) internal returns (bool) {
        return intake.deliverRaw(address(c), _cb(rid, a, sig));
    }
}
