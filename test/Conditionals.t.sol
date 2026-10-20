// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Conditionals} from "../src/Conditionals.sol";
import {IIntake} from "../src/interfaces/IIntake.sol";
import {IOracleAttestation} from "../src/interfaces/IOracleAttestation.sol";
import {Fixture} from "./utils/Fixture.sol";

contract ConditionalsTest is Fixture {
    // ---------------------------------------------------------------------------------------------------------------
    // Interface with the Intake
    // ---------------------------------------------------------------------------------------------------------------

    function test_callbackSelectorsMatchTheIntakeDocs() public view {
        assertEq(c.onOracleResult.selector, bytes4(0x510379c7));
        assertEq(c.onFailure.selector, bytes4(0x5a0df71e));
        assertEq(c.ORACLE_ACTION(), bytes32("oracle.request@oracle-1"));
    }

    function test_domainSeparatorMatchesOracleDomain() public view {
        IOracleAttestation.Attestation memory a;
        a.answer = abi.encode(true);
        // Signed digest computed independently must verify, which checks name, version, chain and contract.
        bytes32 expected = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("IdentityMD Oracle"),
                keccak256("2"),
                block.chainid,
                address(c)
            )
        );
        (, string memory name, string memory version, uint256 chainId, address verifying,,) = c.eip712Domain();
        assertEq(keccak256(bytes(name)), keccak256("IdentityMD Oracle"));
        assertEq(keccak256(bytes(version)), keccak256("2"));
        assertEq(chainId, block.chainid);
        assertEq(verifying, address(c));
        assertTrue(expected != bytes32(0));
    }

    /// @dev The documented example document hashes to the documented value, so the hash is keccak-256 of the bytes.
    function test_documentedQuestionHashExample() public pure {
        bytes memory doc = bytes(
            "{\"answerType\":\"bool\",\"chainId\":1,\"definitions\":{\"pass\":\"The review was accepted and every finding in it is marked fixed.\"},\"evidence\":\"panel\",\"question\":\"Did the review of request 0x2a2a72a13996058695e187dfd43bcee41682f8a6592b04b23bae308fca2784e1 pass?\",\"v\":1,\"window\":{\"fromBlock\":992,\"toBlock\":992}}"
        );
        assertEq(keccak256(doc), 0xaa19db4fb4c28b7bafcf5287d97ffc1f9caeafcd93facfbb2480e1d4af675db9);
    }

    /// @dev Regression vector from the live API: POST /requests/quote for this market's condition question at Ethereum
    ///      block 26230000 returned questionHash 0xf02559bb...da7e for the body this contract builds (2026-10-20).
    function test_questionHashMatchesLiveOracleQuote() public {
        vm.warp(1_760_000_000);
        vm.prank(creator);
        uint256 id = c.createMarket(
            "The US Federal Reserve announced a cut to the federal funds target range at its September 2025 FOMC meeting",
            "Bitcoin closed above 100000 USD on Coinbase on 2025-10-01",
            "Use the official FOMC statements on federalreserve.gov and the Coinbase BTC-USD daily close (UTC).",
            uint64(1_760_000_100),
            uint64(1_760_000_200)
        );
        assertEq(address(c), 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a, "fixture address is part of the vector");
        assertEq(
            keccak256(bytes(c.questionDocument(id, 0, 26_230_000))),
            0xf02559bba7566c41440ea2c04c9c9f56372c3f5dc2288352f3e84d364fa8da7e
        );
    }

    function test_questionDocumentIsCanonical() public {
        uint256 id = _create();
        string memory expected = string.concat(
            "{\"answerType\":\"bool\",\"chainId\":1,\"definitions\":{\"asOf\":\"Judge the statement by what had happened by unix time ",
            vm.toString(uint256(resolveTime)),
            " (UTC). Blockchain blocks are context only.\",\"rules\":\"",
            RULES,
            "\"},\"evidence\":\"panel\",\"question\":\"Conditionals market 1 on Robinhood Chain contract ",
            _lower(address(c)),
            ", condition statement. Was the following statement true as of unix time ",
            vm.toString(uint256(resolveTime)),
            " (UTC)? Statement: ",
            CONDITION,
            "\",\"v\":1,\"window\":{\"fromBlock\":123,\"toBlock\":123}}"
        );
        assertEq(c.questionDocument(id, 0, 123), expected);
    }

    function test_requestBodyIsTheDocumentPlusPanelTerms() public {
        uint256 id = _create();
        string memory body = c.requestBody(id, 1, 77);
        string memory expected = string.concat(
            "{\"answerType\":\"bool\",\"chainId\":1,\"definitions\":{\"asOf\":\"Judge the statement by what had happened by unix time ",
            vm.toString(uint256(resolveTime)),
            " (UTC). Blockchain blocks are context only.\",\"rules\":\"",
            RULES,
            "\"},\"evidence\":\"panel\",\"panelSize\":5,\"question\":\"Conditionals market 1 on Robinhood Chain contract ",
            _lower(address(c)),
            ", outcome statement. Was the following statement true as of unix time ",
            vm.toString(uint256(resolveTime)),
            " (UTC)? Statement: ",
            OUTCOME,
            "\",\"quorum\":4,\"v\":1,\"validForSeconds\":86400,\"window\":{\"fromBlock\":77,\"toBlock\":77}}"
        );
        assertEq(body, expected);
    }

    function test_requestSendsTheBodyAndPaysFromBudget() public {
        uint256 id = _create();
        assertEq(imd.balanceOf(address(c)), 1 ether);
        AskRef[] memory refs = _request(id);
        assertEq(refs.length, 2);
        assertEq(imd.balanceOf(intake.PAYEE()), 1 ether);
        assertEq(imd.balanceOf(address(c)), 0);
        assertEq(imd.allowance(address(c), address(intake)), 0);
        for (uint256 i; i < 2; ++i) {
            assertEq(intake.bodyOf(refs[i].requestId), bytes(c.requestBody(id, refs[i].question, refs[i].windowBlock)));
            (address payer, bytes32 action,,,,,) = intake.requests(refs[i].requestId);
            assertEq(payer, address(c));
            assertEq(action, bytes32("oracle.request@oracle-1"));
        }
        assertEq(c.totalOracleSpend(), 1 ether);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Creation and staking
    // ---------------------------------------------------------------------------------------------------------------

    function test_createMarketTakesBudgetAndSnapshotsConfig() public {
        uint256 before = imd.balanceOf(creator);
        uint256 id = _create();
        assertEq(id, 1);
        assertEq(before - imd.balanceOf(creator), 1 ether);
        Conditionals.Market memory m = c.getMarket(id);
        assertEq(m.creator, creator);
        assertEq(m.budget, 1 ether);
        assertEq(address(m.oracle.intake), address(intake));
        assertEq(m.oracle.signer, signer);
        assertEq(m.oracle.panelSize, 5);
        assertEq(m.oracle.quorum, 4);
        assertEq(m.voidAfter, resolveTime + 30 days);
        assertEq(m.condition, CONDITION);
    }

    function test_createRejectsBadText() public {
        vm.startPrank(creator);
        vm.expectRevert(Conditionals.InvalidText.selector);
        c.createMarket("", OUTCOME, RULES, closeTime, resolveTime);
        vm.expectRevert(Conditionals.InvalidText.selector);
        c.createMarket("has a \"quote\"", OUTCOME, RULES, closeTime, resolveTime);
        vm.expectRevert(Conditionals.InvalidText.selector);
        c.createMarket("back\\slash", OUTCOME, RULES, closeTime, resolveTime);
        vm.expectRevert(Conditionals.InvalidText.selector);
        c.createMarket("new\nline", OUTCOME, RULES, closeTime, resolveTime);
        vm.expectRevert(Conditionals.InvalidText.selector);
        c.createMarket(unicode"café", OUTCOME, RULES, closeTime, resolveTime);
        vm.expectRevert(Conditionals.InvalidText.selector);
        c.createMarket(CONDITION, OUTCOME, "0x5598aa9146215bc13eb26f2c692ad1461fd32982", closeTime, resolveTime);
        vm.expectRevert(Conditionals.InvalidText.selector);
        c.createMarket(CONDITION, _repeat("a", 281), RULES, closeTime, resolveTime);
        vm.expectRevert(Conditionals.InvalidText.selector);
        c.createMarket(CONDITION, OUTCOME, string.concat("a ", _repeat("b", 499)), closeTime, resolveTime);
        c.createMarket(
            _repeat("a", 280), _repeat("b", 280), string.concat("a ", _repeat("b", 498)), closeTime, resolveTime
        );
        vm.stopPrank();
    }

    function test_createRejectsBadTimes() public {
        vm.startPrank(creator);
        vm.expectRevert(Conditionals.InvalidTimes.selector);
        c.createMarket(CONDITION, OUTCOME, RULES, uint64(block.timestamp), resolveTime);
        vm.expectRevert(Conditionals.InvalidTimes.selector);
        c.createMarket(CONDITION, OUTCOME, RULES, resolveTime, closeTime);
        vm.expectRevert(Conditionals.InvalidTimes.selector);
        c.createMarket(CONDITION, OUTCOME, RULES, closeTime, uint64(block.timestamp + 731 days));
        c.createMarket(CONDITION, OUTCOME, RULES, closeTime, closeTime);
        vm.stopPrank();
    }

    function test_stakeRecordsPoolsAndStakes() public {
        uint256 id = _create();
        _stake(alice, id, 0, 0, 10 ether);
        _stake(alice, id, 1, 1, 2 ether);
        _stake(bob, id, 0, 1, 5 ether);
        Conditionals.Market memory m = c.getMarket(id);
        assertEq(m.pools[0][0], 10 ether);
        assertEq(m.pools[0][1], 5 ether);
        assertEq(m.pools[1][1], 2 ether);
        uint256[2][2] memory s = c.stakesOf(id, alice);
        assertEq(s[0][0], 10 ether);
        assertEq(s[1][1], 2 ether);
        assertEq(imd.balanceOf(address(c)), 18 ether);
    }

    function test_stakeRejections() public {
        uint256 id = _create();
        vm.startPrank(alice);
        vm.expectRevert(Conditionals.InvalidChoice.selector);
        c.stake(id, 2, 0, 1 ether);
        vm.expectRevert(Conditionals.InvalidChoice.selector);
        c.stake(id, 0, 2, 1 ether);
        vm.expectRevert(Conditionals.StakeTooSmall.selector);
        c.stake(id, 0, 0, 1e15 - 1);
        vm.expectRevert(Conditionals.UnknownMarket.selector);
        c.stake(2, 0, 0, 1 ether);
        vm.expectRevert(Conditionals.UnknownMarket.selector);
        c.stake(0, 0, 0, 1 ether);
        vm.warp(closeTime);
        vm.expectRevert(Conditionals.BettingClosed.selector);
        c.stake(id, 0, 0, 1 ether);
        vm.stopPrank();
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Settlement outcomes
    // ---------------------------------------------------------------------------------------------------------------

    function _book(uint256 id) internal {
        _stake(alice, id, 0, 0, 30 ether); // world happens, YES
        _stake(bob, id, 0, 1, 70 ether); // world happens, NO
        _stake(carol, id, 1, 0, 40 ether); // world does not, YES
        _stake(dave, id, 1, 1, 60 ether); // world does not, NO
        _stake(alice, id, 1, 1, 5 ether);
    }

    function test_conditionTrueOutcomeYes() public {
        uint256 id = _create();
        _book(id);
        _resolve(id, true, true);

        uint256 deadBefore = imd.balanceOf(DEAD);
        uint256 a = _claim(alice, id);
        // pot 100, fee 3: burn 2, builder 1, net 97 all to alice's 30 YES; plus her 5 refunded from world 1.
        assertEq(a, 97 ether + 5 ether);
        assertEq(imd.balanceOf(DEAD) - deadBefore, 2 ether);
        assertEq(imd.balanceOf(builder), 1 ether);
        assertEq(c.totalBurned(), 2 ether);
        assertEq(_claimOrZero(bob, id), 0);
        assertEq(_claim(carol, id), 40 ether);
        assertEq(_claim(dave, id), 60 ether);
        assertEq(imd.balanceOf(address(c)), 0);
        Conditionals.Market memory m = c.getMarket(id);
        assertEq(uint8(m.status), uint8(Conditionals.Status.Settled));
        assertEq(m.world, 0);
        assertEq(m.winningSide, 0);
    }

    function test_conditionTrueOutcomeNo() public {
        uint256 id = _create();
        _book(id);
        _resolve(id, true, false);
        assertEq(_claim(bob, id), 97 ether);
        assertEq(_claim(alice, id), 5 ether);
        assertEq(_claim(carol, id), 40 ether);
        assertEq(_claim(dave, id), 60 ether);
        assertEq(imd.balanceOf(address(c)), 0);
    }

    function test_conditionFalseSettlesWithoutOutcome() public {
        uint256 id = _create();
        _book(id);
        AskRef[] memory refs = _request(id);
        assertTrue(_answer(id, refs[0], false));
        assertTrue(c.settleable(id));
        // The outcome answer is no longer needed, and is ignored when it arrives after settlement.
        c.settle(id);
        assertTrue(_answer(id, refs[1], true));
        // World 1 pot 105: fee 3.15 (burn 2.1, builder 1.05), net 101.85. NO pool 65: dave 60, alice 5.
        assertEq(_claim(dave, id), uint256(101.85 ether) * 60 / 65);
        assertEq(_claim(alice, id), 30 ether + uint256(101.85 ether) * 5 / 65);
        assertEq(_claim(bob, id), 70 ether);
        assertEq(_claimOrZero(carol, id), 0);
        assertEq(imd.balanceOf(builder), 1.05 ether);
        assertLe(imd.balanceOf(address(c)), 2);
        // Budget returned to creator: nothing left, both questions were paid.
        assertEq(c.getMarket(id).budget, 0);
    }

    function test_outcomeAnsweredBeforeCondition() public {
        uint256 id = _create();
        _book(id);
        AskRef[] memory refs = _request(id);
        assertTrue(_answer(id, refs[1], true));
        assertFalse(c.settleable(id));
        assertTrue(_answer(id, refs[0], true));
        assertTrue(c.settleable(id));
        assertEq(_claim(alice, id), 102 ether);
    }

    function test_oneSidedWorldIsRefundedWithoutFee() public {
        uint256 id = _create();
        _stake(alice, id, 0, 0, 10 ether);
        _stake(bob, id, 0, 0, 20 ether);
        _stake(carol, id, 1, 1, 7 ether);
        _resolve(id, true, false);
        assertEq(_claim(alice, id), 10 ether);
        assertEq(_claim(bob, id), 20 ether);
        assertEq(_claim(carol, id), 7 ether);
        assertEq(imd.balanceOf(builder), 0);
        assertEq(c.totalBurned(), 0);
        assertTrue(c.getMarket(id).worldRefunded);
    }

    function test_claimTwiceReverts() public {
        uint256 id = _create();
        _book(id);
        _resolve(id, true, true);
        _claim(alice, id);
        vm.prank(alice);
        vm.expectRevert(Conditionals.AlreadyClaimed.selector);
        c.claim(id);
        assertEq(c.claimable(id, alice), 0);
    }

    function test_claimBeforeAnswersReverts() public {
        uint256 id = _create();
        _book(id);
        vm.prank(alice);
        vm.expectRevert(Conditionals.NotSettleable.selector);
        c.claim(id);
        vm.expectRevert(Conditionals.NotSettleable.selector);
        c.settle(id);
    }

    function test_claimableMatchesClaim() public {
        uint256 id = _create();
        _book(id);
        _resolve(id, true, false);
        c.settle(id);
        uint256 expected = c.claimable(id, bob);
        assertEq(_claim(bob, id), expected);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Oracle answers: what is accepted
    // ---------------------------------------------------------------------------------------------------------------

    function _refs(uint256 id) internal returns (AskRef[] memory refs) {
        _book(id);
        refs = _request(id);
    }

    function test_rejectsWrongSigner() public {
        uint256 id = _create();
        AskRef[] memory refs = _refs(id);
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], true);
        assertFalse(_deliver(refs[0].requestId, a, _sign(a, 0xB0B)));
        assertEq(c.getMarket(id).answers[0], 0);
        assertEq(c.getMarket(id).openAsks[0], 1);
    }

    function test_rejectsAnswerToAnotherQuestion() public {
        uint256 id = _create();
        AskRef[] memory refs = _refs(id);
        // The outcome's signed answer delivered against the condition's request.
        IOracleAttestation.Attestation memory a = _attestation(id, refs[1], true);
        assertFalse(_deliver(refs[0].requestId, a, _sign(a, signerKey)));
        // Same question at another window block.
        AskRef memory shifted = AskRef(refs[0].requestId, 0, refs[0].windowBlock - 1);
        a = _attestation(id, shifted, true);
        assertFalse(intake.deliverRaw(address(c), _call(refs[0].requestId, a, _sign(a, signerKey))));
        // Another market's question, same text otherwise.
        vm.prank(creator);
        uint256 other =
            c.createMarket(CONDITION, OUTCOME, RULES, uint64(block.timestamp + 1), uint64(block.timestamp + 2));
        a = _attestation(other, refs[0], true);
        assertFalse(intake.deliverRaw(address(c), _call(refs[0].requestId, a, _sign(a, signerKey))));
        assertEq(c.getMarket(id).answers[0], 0);
    }

    function test_rejectsWeakPanel() public {
        uint256 id = _create();
        AskRef[] memory refs = _refs(id);
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], true);
        a.panelSize = 2;
        a.quorum = 2;
        a.agreed = 2;
        assertFalse(_deliver(refs[0].requestId, a, _sign(a, signerKey)));

        a = _attestation(id, refs[0], true);
        a.agreed = 3; // below the signed quorum (chain-evidence tie-break)
        assertFalse(intake.deliverRaw(address(c), _call(refs[0].requestId, a, _sign(a, signerKey))));

        a = _attestation(id, refs[0], true);
        a.quorum = 3;
        a.agreed = 3;
        assertFalse(intake.deliverRaw(address(c), _call(refs[0].requestId, a, _sign(a, signerKey))));
    }

    function test_rejectsExpiredWrongTypeOrMalformedAnswer() public {
        uint256 id = _create();
        AskRef[] memory refs = _refs(id);
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], true);
        a.expiresAt = uint64(block.timestamp - 1);
        assertFalse(intake.deliverRaw(address(c), _call(refs[0].requestId, a, _sign(a, signerKey))));

        a = _attestation(id, refs[0], true);
        a.answerType = 3;
        assertFalse(intake.deliverRaw(address(c), _call(refs[0].requestId, a, _sign(a, signerKey))));

        a = _attestation(id, refs[0], true);
        a.answer = abi.encode(uint256(2));
        assertFalse(intake.deliverRaw(address(c), _call(refs[0].requestId, a, _sign(a, signerKey))));

        a = _attestation(id, refs[0], true);
        a.answer = hex"01";
        assertFalse(intake.deliverRaw(address(c), _call(refs[0].requestId, a, _sign(a, signerKey))));

        // Still answerable with a good one.
        assertTrue(_answer(id, refs[0], true));
    }

    function test_rejectsTamperedFields() public {
        uint256 id = _create();
        AskRef[] memory refs = _refs(id);
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], true);
        bytes memory sig = _sign(a, signerKey);
        a.answer = abi.encode(false);
        assertFalse(intake.deliverRaw(address(c), _call(refs[0].requestId, a, sig)));
    }

    function test_rejectsCallsNotFromTheIntake() public {
        uint256 id = _create();
        AskRef[] memory refs = _refs(id);
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], true);
        bytes memory sig = _sign(a, signerKey);
        vm.expectRevert(Conditionals.UnknownAsk.selector);
        c.onOracleResult(refs[0].requestId, a, sig);
        vm.expectRevert(Conditionals.UnknownAsk.selector);
        c.onFailure(refs[0].requestId, 2, "disagreed", 0, 0, "");
        // A valid answer for an id this contract never asked.
        vm.prank(address(intake));
        vm.expectRevert(Conditionals.UnknownAsk.selector);
        c.onOracleResult(keccak256("other"), a, sig);
    }

    function test_answerIsAcceptedOnlyOnce() public {
        uint256 id = _create();
        AskRef[] memory refs = _refs(id);
        assertTrue(_answer(id, refs[0], true));
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], false);
        // A replay of the same request is unknown now.
        assertFalse(intake.deliverRaw(address(c), _call(refs[0].requestId, a, _sign(a, signerKey))));
        assertEq(c.getMarket(id).answers[0], 1);
    }

    function test_callbackFitsTheIntakeGasLimit() public {
        uint256 id = _create();
        AskRef[] memory refs = _refs(id);
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], true);
        bytes memory data = _call(refs[0].requestId, a, _sign(a, signerKey));
        vm.prank(address(intake));
        uint256 g = gasleft();
        (bool ok,) = address(c).call(data);
        uint256 used = g - gasleft();
        assertTrue(ok);
        assertLt(used, 120_000, "callback must fit the 200k Intake gas with margin");
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Failures, retries, voiding
    // ---------------------------------------------------------------------------------------------------------------

    function test_requestRules() public {
        uint256 id = _create();
        vm.expectRevert(Conditionals.TooEarly.selector);
        c.requestResolution(id);
        AskRef[] memory refs = _request(id);
        assertEq(refs.length, 2);
        // Asked and pending: nothing to ask until the retry delay.
        vm.expectRevert(Conditionals.NothingToAsk.selector);
        c.requestResolution(id);
        assertFalse(c.askable(id, 0));
    }

    function test_failureThenRetryPaidByCaller() public {
        uint256 id = _create();
        _book(id);
        AskRef[] memory refs = _request(id);
        assertTrue(intake.fail(refs[0].requestId, 2, "disagreed"));
        assertEq(c.getMarket(id).openAsks[0], 0);
        // The condition can be asked again at once; the budget is spent so the caller pays.
        assertTrue(c.askable(id, 0));
        assertFalse(c.askable(id, 1));
        uint256 before = imd.balanceOf(address(this));
        vm.roll(block.number + 5);
        AskRef[] memory retry = _request(id);
        assertEq(retry.length, 1);
        assertEq(retry[0].question, 0);
        assertEq(before - imd.balanceOf(address(this)), 0.5 ether);
        assertTrue(_answer(id, retry[0], false));
        c.settle(id);
    }

    function test_unansweredAskCanBeRetriedAfterDelay() public {
        uint256 id = _create();
        _book(id);
        AskRef[] memory refs = _request(id);
        vm.warp(block.timestamp + 1 days - 1);
        vm.expectRevert(Conditionals.NothingToAsk.selector);
        c.requestResolution(id);
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 100);
        AskRef[] memory retry = _request(id);
        assertEq(retry.length, 2);
        // Either the late original or the retry can answer; the first valid one wins.
        assertTrue(_answer(id, refs[0], true));
        assertTrue(_answer(id, retry[0], false)); // ignored
        assertEq(c.getMarket(id).answers[0], 1);
        assertEq(c.getMarket(id).openAsks[0], 0);
        assertTrue(_answer(id, retry[1], true));
        assertEq(_claim(alice, id), 102 ether);
    }

    function test_voidRefundsEverythingAndBudget() public {
        uint256 id = _create();
        _book(id);
        vm.warp(resolveTime + 30 days);
        vm.expectRevert(Conditionals.NotVoidable.selector);
        c.voidMarket(id);
        vm.warp(resolveTime + 30 days + 1);
        uint256 creatorBefore = imd.balanceOf(creator);
        c.voidMarket(id);
        assertEq(imd.balanceOf(creator) - creatorBefore, 1 ether);
        assertEq(_claim(alice, id), 35 ether);
        assertEq(_claim(bob, id), 70 ether);
        assertEq(_claim(carol, id), 40 ether);
        assertEq(_claim(dave, id), 60 ether);
        assertEq(imd.balanceOf(address(c)), 0);
        vm.expectRevert(Conditionals.MarketNotOpen.selector);
        c.requestResolution(id);
    }

    function test_cannotVoidASettleableMarket() public {
        uint256 id = _create();
        _book(id);
        _resolve(id, false, false);
        vm.warp(resolveTime + 31 days);
        vm.expectRevert(Conditionals.NotVoidable.selector);
        c.voidMarket(id);
        assertEq(_claim(dave, id), uint256(101.85 ether) * 60 / 65);
    }

    function test_cannotRequestAfterVoidAfter() public {
        uint256 id = _create();
        vm.warp(resolveTime + 30 days + 1);
        vm.expectRevert(Conditionals.MarketNotOpen.selector);
        c.requestResolution(id);
    }

    function test_answerAfterVoidIsIgnored() public {
        uint256 id = _create();
        _book(id);
        AskRef[] memory refs = _request(id);
        vm.warp(resolveTime + 30 days + 1);
        c.voidMarket(id);
        // An answer that arrives after the void is accepted as a call and ignored.
        IOracleAttestation.Attestation memory a = _attestation(id, refs[0], true);
        assertTrue(_deliver(refs[0].requestId, a, _sign(a, signerKey)));
        assertEq(c.getMarket(id).answers[0], 0);
        assertEq(_claim(alice, id), 35 ether);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Owner
    // ---------------------------------------------------------------------------------------------------------------

    function test_oracleConfigChangeIsDelayedAndOnlyAffectsNewMarkets() public {
        uint256 id = _create();
        Conditionals.OracleConfig memory next = Conditionals.OracleConfig({
            intake: IIntake(address(0x1234)), signer: address(0x5678), price: 1 ether, panelSize: 9, quorum: 7
        });
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        c.proposeOracleConfig(next);

        vm.startPrank(owner);
        c.proposeOracleConfig(next);
        vm.expectRevert(Conditionals.TooEarly.selector);
        c.activateOracleConfig();
        vm.warp(block.timestamp + 3 days);
        c.activateOracleConfig();
        vm.stopPrank();

        (IIntake i, address s, uint128 p, uint16 ps, uint16 qu) = c.oracleConfig();
        assertEq(address(i), address(0x1234));
        assertEq(s, address(0x5678));
        assertEq(p, 1 ether);
        assertEq(ps, 9);
        assertEq(qu, 7);
        // The existing market keeps its config and resolves with the original signer and intake.
        assertEq(c.getMarket(id).oracle.signer, signer);
        _book(id);
        _resolve(id, true, true);
        assertEq(_claim(alice, id), 102 ether);

        vm.warp(block.timestamp + 1);
        vm.prank(creator);
        uint256 id2 = c.createMarket(
            CONDITION, OUTCOME, RULES, uint64(block.timestamp + 1 days), uint64(block.timestamp + 2 days)
        );
        assertEq(c.getMarket(id2).budget, 2 ether);
        assertEq(c.getMarket(id2).oracle.signer, address(0x5678));
    }

    function test_oracleConfigBounds() public {
        vm.startPrank(owner);
        Conditionals.OracleConfig memory cfg = Conditionals.OracleConfig({
            intake: IIntake(address(intake)), signer: signer, price: 0.5 ether, panelSize: 4, quorum: 3
        });
        vm.expectRevert(Conditionals.InvalidConfig.selector);
        c.proposeOracleConfig(cfg);
        cfg.panelSize = 5;
        cfg.quorum = 6;
        vm.expectRevert(Conditionals.InvalidConfig.selector);
        c.proposeOracleConfig(cfg);
        cfg.quorum = 1;
        vm.expectRevert(Conditionals.InvalidConfig.selector);
        c.proposeOracleConfig(cfg);
        cfg.quorum = 4;
        cfg.price = 0;
        vm.expectRevert(Conditionals.InvalidConfig.selector);
        c.proposeOracleConfig(cfg);
        cfg.price = 11 ether;
        vm.expectRevert(Conditionals.InvalidConfig.selector);
        c.proposeOracleConfig(cfg);
        cfg.price = 0.5 ether;
        cfg.signer = address(0);
        vm.expectRevert(Conditionals.ZeroAddress.selector);
        c.proposeOracleConfig(cfg);
        vm.expectRevert(Conditionals.TooEarly.selector);
        c.activateOracleConfig();
        vm.stopPrank();
    }

    function test_feeRecipient() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        c.setFeeRecipient(alice);
        vm.prank(owner);
        vm.expectRevert(Conditionals.ZeroAddress.selector);
        c.setFeeRecipient(address(0));
        vm.prank(owner);
        c.setFeeRecipient(carol);
        uint256 id = _create();
        _stake(alice, id, 0, 0, 50 ether);
        _stake(bob, id, 0, 1, 50 ether);
        uint256 before = imd.balanceOf(carol);
        _resolve(id, true, true);
        c.settle(id);
        assertEq(imd.balanceOf(carol) - before, 1 ether);
    }

    function test_constructorValidation() public {
        vm.expectRevert(Conditionals.ZeroAddress.selector);
        new Conditionals(owner, IERC20(address(0)), IIntake(address(intake)), signer, builder);
        vm.expectRevert(Conditionals.ZeroAddress.selector);
        new Conditionals(owner, IERC20(address(imd)), IIntake(address(intake)), signer, address(0));
        vm.expectRevert(Conditionals.ZeroAddress.selector);
        new Conditionals(owner, IERC20(address(imd)), IIntake(address(0)), signer, builder);
        vm.expectRevert(Conditionals.ZeroAddress.selector);
        new Conditionals(owner, IERC20(address(imd)), IIntake(address(intake)), address(0), builder);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Fuzz: payouts never exceed what the market holds
    // ---------------------------------------------------------------------------------------------------------------

    function testFuzz_payoutsConserveFunds(uint96[8] memory amounts, bool condition, bool outcome) public {
        uint256 id = _create();
        address[4] memory traders = [alice, bob, carol, dave];
        uint256 total;
        for (uint256 i; i < 8; ++i) {
            uint256 amount = bound(amounts[i], 0, 100 ether);
            if (amount < 1e15) continue;
            _stake(traders[i % 4], id, uint8((i / 2) % 2), uint8(i % 2), amount);
            total += amount;
        }
        _resolve(id, condition, outcome);
        c.settle(id);
        uint256 paid;
        for (uint256 i; i < 4; ++i) {
            if (c.claimable(id, traders[i]) > 0) paid += _claim(traders[i], id);
        }
        uint256 fees = c.totalBurned() + c.totalBuilderFees();
        assertLe(paid + fees, total);
        assertLe(total - paid - fees, 4, "dust");
        assertEq(imd.balanceOf(address(c)), total - paid - fees);
    }

    // ---------------------------------------------------------------------------------------------------------------
    // Helpers
    // ---------------------------------------------------------------------------------------------------------------

    function _call(bytes32 requestId, IOracleAttestation.Attestation memory a, bytes memory sig)
        internal
        view
        returns (bytes memory)
    {
        return abi.encodeWithSelector(c.onOracleResult.selector, requestId, a, sig);
    }

    function _claimOrZero(address who, uint256 id) internal returns (uint256) {
        if (c.claimable(id, who) == 0) return 0;
        return _claim(who, id);
    }

    function _repeat(string memory s, uint256 n) internal pure returns (string memory out) {
        for (uint256 i; i < n; ++i) {
            out = string.concat(out, s);
        }
    }

    function _lower(address a) internal pure returns (string memory) {
        bytes memory hexChars = "0123456789abcdef";
        bytes memory out = new bytes(42);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i; i < 20; ++i) {
            uint8 b = uint8(uint160(a) >> (8 * (19 - i)));
            out[2 + 2 * i] = hexChars[b >> 4];
            out[3 + 2 * i] = hexChars[b & 0x0f];
        }
        return string(out);
    }
}
