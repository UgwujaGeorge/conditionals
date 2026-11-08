// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ConditionalsFacts as Facts} from "../src/ConditionalsFacts.sol";
import {IIntake} from "../src/interfaces/IIntake.sol";
import {IOracleAttestation} from "../src/interfaces/IOracleAttestation.sol";
import {MockIMD, MockIntake, MockSignerRegistry} from "./utils/Mocks.sol";
import {OracleQuestion, OracleAttestationCodes} from "./utils/OracleQuestion.sol";

abstract contract FactsFixture is Test {
    using Strings for uint256;
    using Strings for address;

    MockIMD internal imd;
    MockIntake internal intake;
    Facts internal c;

    uint256 internal signerKey = 0xA11CE;
    address internal signer;
    address internal owner = makeAddr("owner");
    address internal builder = makeAddr("builder");
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    string internal constant TOPIC = "Bitcoin";
    string internal constant CLAIM = "The Bitcoin protocol caps the total supply of bitcoin at 21 million coins";
    string internal constant RULES = "Judge by the Bitcoin Core source code and the Bitcoin whitepaper.";
    uint256 internal constant B = 10 ether;

    function setUp() public virtual {
        vm.warp(1_790_000_000);
        vm.roll(26_000_000);
        signer = vm.addr(signerKey);
        imd = new MockIMD();
        intake = new MockIntake();
        c = new Facts(owner, IERC20(address(imd)), IIntake(address(intake)), signer, builder);

        address[5] memory users = [creator, alice, bob, carol, address(this)];
        for (uint256 i; i < users.length; ++i) {
            imd.mint(users[i], 1_000 ether);
            vm.prank(users[i]);
            imd.approve(address(c), type(uint256).max);
        }
    }

    function _create() internal returns (uint256 id) {
        vm.prank(creator);
        id = c.createFact(TOPIC, CLAIM, RULES, B);
    }

    function _buy(address who, uint256 id, uint8 side, uint256 amount) internal returns (uint256) {
        vm.prank(who);
        return c.buy(id, side, amount, 0);
    }

    struct AskRef {
        bytes32 requestId;
        uint32 round;
        uint64 askedAt;
        uint256 windowBlock;
    }

    function _challenge(address who, uint256 id) internal returns (AskRef memory ref) {
        ref.round = c.getFact(id).rounds;
        ref.askedAt = uint64(block.timestamp);
        ref.windowBlock = block.number - 10;
        vm.prank(who);
        ref.requestId = c.challenge(id, 10 ether);
    }

    function _attestation(uint256 id, AskRef memory ref, bool value)
        internal
        view
        returns (IOracleAttestation.Attestation memory a)
    {
        a.requestId = bytes32(bytes16(keccak256(abi.encode("oracle", ref.requestId))));
        a.chainId = 1;
        a.questionHash = keccak256(bytes(c.questionDocument(id, ref.round, ref.askedAt, ref.windowBlock)));
        a.answerType = 0;
        a.answer = abi.encode(value);
        a.fromBlock = uint64(ref.windowBlock);
        a.toBlock = uint64(ref.windowBlock);
        a.blockHash = keccak256("block");
        a.panelJobId = bytes32(bytes16(keccak256("panel")));
        a.panelSize = 5;
        a.quorum = 4;
        a.agreed = 5;
        a.issuedAt = uint64(block.timestamp);
        a.expiresAt = uint64(block.timestamp + 1 days);
    }

    /// @dev EIP-712 digest computed independently of the contract under test.
    function _digest(IOracleAttestation.Attestation memory a) internal view returns (bytes32) {
        bytes32 domain = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("IdentityMD Oracle"),
                keccak256("2"),
                block.chainid,
                address(c)
            )
        );
        bytes32 typehash = keccak256(
            "OracleAttestation(bytes32 requestId,uint256 chainId,bytes32 questionHash,uint8 answerType,bytes answer,"
            "uint256 figure,uint64 fromBlock,uint64 toBlock,bytes32 blockHash,bytes32 panelJobId,uint16 panelSize,"
            "uint16 quorum,uint16 agreed,uint64 issuedAt,uint64 expiresAt)"
        );
        bytes32 structHash = keccak256(
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
        return keccak256(abi.encodePacked("\x19\x01", domain, structHash));
    }

    function _sign(IOracleAttestation.Attestation memory a, uint256 key) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, _digest(a));
        return abi.encodePacked(r, s, v);
    }

    function _deliver(AskRef memory ref, IOracleAttestation.Attestation memory a, bytes memory sig)
        internal
        returns (bool)
    {
        return intake.complete(ref.requestId, abi.encode(a, sig));
    }

    function _answer(uint256 id, AskRef memory ref, bool value) internal returns (bool) {
        IOracleAttestation.Attestation memory a = _attestation(id, ref, value);
        return _deliver(ref, a, _sign(a, signerKey));
    }

    function _judge(uint256 id, bool value) internal returns (AskRef memory ref) {
        ref = _challenge(carol, id);
        assertTrue(_answer(id, ref, value), "answer not delivered");
    }

    function _phase(uint256 id, uint32 round) internal view returns (Facts.Phase) {
        return c.getRound(id, round).phase;
    }

    /// @dev The question the contract asks, built with the protocol's reference library.
    function _reference(uint256 id, uint32 round, uint64 askedAt, uint256 windowBlock)
        internal
        view
        returns (OracleQuestion.Question memory q)
    {
        Facts.Fact memory f = c.getFact(id);
        q.question = string.concat(
            "Conditionals encyclopedia fact ",
            id.toString(),
            " round ",
            uint256(round).toString(),
            " on Robinhood Chain contract ",
            address(c).toHexString(),
            ". Was the following statement true as of unix time ",
            uint256(askedAt).toString(),
            " (UTC)? Statement: ",
            f.claim
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
                "Judge the statement by what was true at unix time ",
                uint256(askedAt).toString(),
                " (UTC). Blockchain blocks are context only."
            )
        );
        q.definitions[1] = OracleQuestion.Definition("rules", f.rules);
    }
}

contract ConditionalsFactsTest is FactsFixture {
    uint256 internal constant SEED_10 = 6_931_471_805_599_453_094; // 10 ln 2

    // ---- creation --------------------------------------------------------------------------------------------------

    function test_create_takesTheSeedAndOpensRoundOne() public {
        uint256 before = imd.balanceOf(creator);
        uint256 id = _create();
        assertEq(id, 1);
        Facts.Fact memory f = c.getFact(id);
        assertEq(f.creator, creator);
        assertEq(f.rounds, 1);
        assertEq(f.b, B);
        assertEq(f.topic, TOPIC);
        assertEq(f.claim, CLAIM);
        assertEq(f.rules, RULES);
        assertEq(f.verdict, 0);

        Facts.Round memory r = c.getRound(id, 1);
        assertEq(r.seeder, creator);
        assertEq(uint8(r.phase), uint8(Facts.Phase.Open));
        assertApproxEqAbs(r.seed, SEED_10, 200);
        assertEq(r.makerBalance, r.seed);
        assertEq(before - imd.balanceOf(creator), r.seed);

        uint256[2] memory p = c.prices(id, 1);
        assertApproxEqAbs(p[0], 0.5 ether, 2);
        assertApproxEqAbs(p[1], 0.5 ether, 2);
        assertTrue(c.trading(id));
    }

    function test_create_validates() public {
        vm.startPrank(creator);
        vm.expectRevert(Facts.InvalidConfig.selector);
        c.createFact(TOPIC, CLAIM, RULES, 0.1 ether - 1);
        vm.expectRevert(Facts.InvalidConfig.selector);
        c.createFact(TOPIC, CLAIM, RULES, 100 ether + 1);
        vm.expectRevert(Facts.InvalidText.selector);
        c.createFact("", CLAIM, RULES, B);
        vm.expectRevert(Facts.InvalidText.selector);
        c.createFact(string(new bytes(65)), CLAIM, RULES, B);
        vm.expectRevert(Facts.InvalidText.selector);
        c.createFact(TOPIC, 'a "quoted" claim', RULES, B);
        vm.expectRevert(Facts.InvalidText.selector);
        c.createFact(TOPIC, CLAIM, "nospaceatall", B);
        vm.expectRevert(Facts.InvalidText.selector);
        c.createFact(TOPIC, CLAIM, string(new bytes(501)), B);
        vm.stopPrank();
    }

    function test_seedFor_isbln2() public view {
        assertApproxEqAbs(c.seedFor(B), SEED_10, 200);
        assertApproxEqRel(c.seedFor(0.1 ether), 0.0693 ether, 0.001e18);
    }

    function test_unknownFact() public {
        vm.expectRevert(Facts.UnknownFact.selector);
        c.getFact(1);
        vm.expectRevert(Facts.UnknownFact.selector);
        c.buy(1, 0, 1 ether, 0);
        assertFalse(c.trading(1));
    }

    // ---- trading ---------------------------------------------------------------------------------------------------

    function test_buy_matchesQuoteAndSplitsTheFee() public {
        uint256 id = _create();
        (uint256 quoted, uint256 cost, uint256 fee) = c.quoteBuy(id, 0, 5 ether);
        uint256 before = imd.balanceOf(alice);
        uint256 burned = imd.balanceOf(DEAD);
        uint256 k = _buy(alice, id, 0, 5 ether);
        assertEq(k, quoted);
        assertEq(before - imd.balanceOf(alice), cost + fee);
        assertLe(cost + fee, 5 ether);
        assertGe(cost + fee, 5 ether - 5 ether / 1e8, "spends all but the rounding");
        assertEq(c.sharesOf(id, 1, alice)[0], k);

        assertEq(c.owed(creator), fee * 100 / 200, "half the fee to the seeder");
        assertEq(imd.balanceOf(DEAD) - burned, fee * 67 / 200);
        assertEq(c.owed(builder), fee - fee * 100 / 200 - fee * 67 / 200);

        uint256[2] memory p = c.prices(id, 1);
        assertGt(p[0], 0.6 ether);
        assertApproxEqAbs(p[0] + p[1], 1 ether, 4);
        // Shares are worth more than their price: k > cost.
        assertGt(k, cost);
    }

    function test_buyFor_creditsTheAccountAndChargesTheCaller() public {
        uint256 id = _create();
        uint256 payer = imd.balanceOf(bob);
        uint256 credited = imd.balanceOf(alice);
        vm.prank(bob);
        uint256 k = c.buyFor(alice, id, 1, 2 ether, 0);
        assertLe(payer - imd.balanceOf(bob), 2 ether);
        assertEq(imd.balanceOf(alice), credited);
        assertEq(c.sharesOf(id, 1, alice)[1], k);
        assertEq(c.sharesOf(id, 1, bob)[1], 0);
        vm.prank(bob);
        vm.expectRevert(Facts.ZeroAddress.selector);
        c.buyFor(address(0), id, 1, 2 ether, 0);
    }

    function test_trade_boundsAndSlippage() public {
        uint256 id = _create();
        vm.startPrank(alice);
        vm.expectRevert(Facts.InvalidChoice.selector);
        c.buy(id, 2, 1 ether, 0);
        vm.expectRevert(Facts.TradeTooSmall.selector);
        c.buy(id, 0, 1e15 - 1, 0);
        vm.expectRevert(Facts.SlippageExceeded.selector);
        c.buy(id, 0, 1 ether, 10 ether);
        vm.expectRevert(Facts.TradeTooLarge.selector);
        c.buy(id, 0, 400 ether, 0);
        uint256 k = c.buy(id, 0, 1 ether, 0);
        vm.expectRevert(Facts.SlippageExceeded.selector);
        c.sell(id, 0, k, 1 ether);
        vm.expectRevert(Facts.InvalidChoice.selector);
        c.sell(id, 2, k, 0);
        vm.expectRevert(Facts.TradeTooSmall.selector);
        c.sell(id, 0, 0, 0);
        vm.stopPrank();
    }

    function test_sell_roundTripLosesAndRestoresPrices() public {
        uint256 id = _create();
        uint256 before = imd.balanceOf(alice);
        uint256 k = _buy(alice, id, 0, 5 ether);
        (uint256 quoted,) = c.quoteSell(id, 0, k);
        vm.prank(alice);
        uint256 got = c.sell(id, 0, k, 0);
        assertEq(got, quoted);
        assertLt(imd.balanceOf(alice), before, "fees and rounding are lost");
        assertGt(imd.balanceOf(alice), before - 0.25 ether);
        uint256[2] memory p = c.prices(id, 1);
        assertApproxEqAbs(p[0], 0.5 ether, 2);
        Facts.Round memory r = c.getRound(id, 1);
        assertEq(r.q[0], 0);
        assertGe(r.makerBalance, r.seed, "the maker keeps the rounding");
    }

    function test_sell_moreThanHeldReverts() public {
        uint256 id = _create();
        _buy(alice, id, 0, 5 ether);
        uint256 k = _buy(bob, id, 0, 5 ether);
        vm.prank(bob);
        vm.expectRevert();
        c.sell(id, 0, k + 1, 0);
        vm.prank(carol);
        vm.expectRevert();
        c.sell(id, 0, 1 ether, 0);
    }

    function test_sell_aRemainderBelowTheMinimumCanBeSoldWhole() public {
        uint256 id = _create();
        uint256 k = _buy(alice, id, 0, 1 ether);
        uint256 keep = 1e14;
        vm.startPrank(alice);
        c.sell(id, 0, k - keep, 0);
        vm.expectRevert(Facts.TradeTooSmall.selector);
        c.sell(id, 0, keep - 1, 0);
        c.sell(id, 0, keep, 0);
        vm.stopPrank();
        assertEq(c.sharesOf(id, 1, alice)[0], 0);
    }

    function test_spreadIsBounded() public {
        vm.prank(creator);
        uint256 id = c.createFact(TOPIC, CLAIM, RULES, 0.1 ether);
        // Push TRUE as far as the spread allows; the next buy is refused, not misquoted.
        for (uint256 i; i < 40; ++i) {
            vm.prank(alice);
            try c.buy(id, 0, 1 ether, 0) {} catch {}
        }
        Facts.Round memory r = c.getRound(id, 1);
        assertLe(r.q[0] - r.q[1], 20 * 0.1 ether);
        assertGe(r.makerBalance, uint256(r.q[0]));
    }

    // ---- challenges and verdicts -----------------------------------------------------------------------------------

    function test_challenge_paysTheOracleAndPausesTrading() public {
        uint256 id = _create();
        _buy(alice, id, 0, 5 ether);
        uint256 before = imd.balanceOf(carol);
        AskRef memory ref = _challenge(carol, id);
        assertEq(before - imd.balanceOf(carol), 0.5 ether);
        assertEq(imd.balanceOf(intake.PAYEE()), 0.5 ether);
        assertEq(c.totalOracleSpend(), 0.5 ether);
        assertEq(uint8(_phase(id, 1)), uint8(Facts.Phase.Asking));
        assertFalse(c.trading(id));

        vm.startPrank(alice);
        vm.expectRevert(Facts.NotTrading.selector);
        c.buy(id, 0, 1 ether, 0);
        vm.expectRevert(Facts.NotTrading.selector);
        c.sell(id, 0, 1 ether, 0);
        vm.expectRevert(Facts.NotTrading.selector);
        c.challenge(id, 1 ether);
        vm.stopPrank();

        (uint256 askFact, uint32 askRound, bool live, bytes32 questionHash) =
            c.asks(keccak256(abi.encode(address(intake), ref.requestId)));
        assertEq(askFact, id);
        assertEq(askRound, 1);
        assertTrue(live);
        assertEq(questionHash, OracleQuestion.hash(_reference(id, 1, ref.askedAt, ref.windowBlock)));
    }

    function test_challenge_respectsMaxPriceAndTheLivePrice() public {
        uint256 id = _create();
        intake.setPrice(0.7 ether);
        assertEq(c.challengePrice(id), 0.7 ether);
        vm.prank(carol);
        vm.expectRevert(abi.encodeWithSelector(Facts.PriceTooHigh.selector, 0.7 ether, 0.5 ether));
        c.challenge(id, 0.5 ether);
        uint256 before = imd.balanceOf(carol);
        vm.prank(carol);
        c.challenge(id, 0.7 ether);
        assertEq(before - imd.balanceOf(carol), 0.7 ether);
    }

    function test_challenge_bodyCarriesTheDocumentAndPanelTerms() public {
        uint256 id = _create();
        AskRef memory ref = _challenge(carol, id);
        string memory body = string(intake.bodyOf(ref.requestId));
        OracleQuestion.Question memory q = _reference(id, 1, ref.askedAt, ref.windowBlock);
        assertEq(vm.parseJsonString(body, ".answerType"), "bool");
        assertEq(vm.parseJsonString(body, ".evidence"), "panel");
        assertEq(vm.parseJsonString(body, ".definitions.asOf"), q.definitions[0].value);
        assertEq(vm.parseJsonUint(body, ".panelSize"), 5);
        assertEq(vm.parseJsonUint(body, ".quorum"), 4);
        assertEq(vm.parseJsonUint(body, ".validForSeconds"), 86_400);
        assertEq(vm.parseJsonUint(body, ".v"), 1);
        assertEq(vm.parseJsonString(body, ".question"), q.question);
        assertEq(vm.parseJsonString(body, ".definitions.rules"), RULES);
        assertEq(vm.parseJsonUint(body, ".window.toBlock"), block.number - 10);
    }

    /// forge-config: default.fuzz.runs = 256
    function testFuzz_documentMatchesTheReferenceLibrary(bytes memory claimSeed, bytes memory rulesSeed, uint32 at, uint32 windowBlock)
        public
    {
        string memory claim = _text(claimSeed, 280, false);
        string memory rules = _text(rulesSeed, 500, true);
        vm.prank(creator);
        uint256 id = c.createFact(TOPIC, claim, rules, B);
        bytes memory expected = OracleQuestion.document(_reference(id, 1, at, windowBlock));
        assertEq(bytes(c.questionDocument(id, 1, at, windowBlock)), expected);
    }

    function test_verdictTrue_paysTrueAndCreditsTheSeeder() public {
        uint256 id = _create();
        uint256 kTrue = _buy(alice, id, 0, 5 ether);
        uint256 kFalse = _buy(bob, id, 1, 2 ether);
        uint256 seederFees = c.owed(creator);
        Facts.Round memory before = c.getRound(id, 1);

        AskRef memory ref = _judge(id, true);

        Facts.Round memory r = c.getRound(id, 1);
        assertEq(uint8(r.phase), uint8(Facts.Phase.Settled));
        assertEq(r.winner, 0);
        assertEq(r.makerBalance, kTrue);
        assertEq(c.owed(creator) - seederFees, before.makerBalance - kTrue, "residual to the seeder");

        Facts.Fact memory f = c.getFact(id);
        assertEq(f.verdict, 1);
        assertEq(f.verdictAt, ref.askedAt);

        assertEq(c.redeemable(id, 1, alice), kTrue);
        assertEq(c.redeemable(id, 1, bob), 0);
        uint256 a0 = imd.balanceOf(alice);
        vm.prank(alice);
        assertEq(c.redeem(id, 1), kTrue);
        assertEq(imd.balanceOf(alice) - a0, kTrue);
        vm.prank(alice);
        assertEq(c.redeem(id, 1), 0, "a second redeem pays nothing");
        vm.prank(bob);
        assertEq(c.redeem(id, 1), 0);
        assertEq(c.sharesOf(id, 1, bob)[1], kFalse, "losing shares stay, worthless");

        _drain();
    }

    function test_verdictFalse_paysFalse() public {
        uint256 id = _create();
        _buy(alice, id, 0, 5 ether);
        uint256 kFalse = _buy(bob, id, 1, 2 ether);
        _judge(id, false);
        assertEq(c.getRound(id, 1).winner, 1);
        assertEq(c.getFact(id).verdict, 2);
        vm.prank(bob);
        assertEq(c.redeem(id, 1), kFalse);
        vm.prank(alice);
        assertEq(c.redeem(id, 1), 0);
        _drain();
    }

    function test_redeem_onlyWhenSettled() public {
        uint256 id = _create();
        _buy(alice, id, 0, 1 ether);
        vm.prank(alice);
        vm.expectRevert(Facts.NotSettled.selector);
        c.redeem(id, 1);
        _challenge(carol, id);
        vm.prank(alice);
        vm.expectRevert(Facts.NotSettled.selector);
        c.redeem(id, 1);
    }

    function test_challengeOfAnEmptyRoundReturnsTheSeed() public {
        uint256 id = _create();
        _judge(id, true);
        assertApproxEqAbs(c.owed(creator), c.getRound(id, 1).seed, 0);
        assertEq(c.getRound(id, 1).makerBalance, 0);
    }

    function test_failure_resumesTrading() public {
        uint256 id = _create();
        _buy(alice, id, 0, 1 ether);
        AskRef memory ref = _challenge(carol, id);
        assertTrue(intake.fail(ref.requestId, 1, "ambiguous"));
        assertEq(uint8(_phase(id, 1)), uint8(Facts.Phase.Open));
        assertEq(c.getRound(id, 1).askedAt, 0);
        assertEq(c.getFact(id).verdict, 0);
        assertTrue(c.trading(id));
        _buy(alice, id, 0, 1 ether);
        // And it can be challenged again.
        _judge(id, true);
    }

    function test_timeout_resumesTradingAndIgnoresALateAnswer() public {
        uint256 id = _create();
        uint256 k = _buy(alice, id, 0, 1 ether);
        AskRef memory ref = _challenge(carol, id);
        IOracleAttestation.Attestation memory a = _attestation(id, ref, true);
        bytes memory sig = _sign(a, signerKey);

        vm.warp(block.timestamp + 1 days - 1);
        assertFalse(c.trading(id));
        vm.warp(block.timestamp + 1);
        assertTrue(c.trading(id));
        vm.prank(alice);
        c.sell(id, 0, k, 0);

        assertTrue(_deliver(ref, a, sig), "a late answer is ignored, not refused");
        assertEq(uint8(_phase(id, 1)), uint8(Facts.Phase.Asking), "still past its timeout, so trading");
        assertTrue(c.trading(id));
        assertEq(c.getFact(id).verdict, 0);
        (,, bool live,) = c.asks(keccak256(abi.encode(address(intake), ref.requestId)));
        assertFalse(live, "the late ask is cleared");
    }

    function test_rechallengeAfterTimeoutIgnoresTheOldAsk() public {
        uint256 id = _create();
        AskRef memory first = _challenge(carol, id);
        IOracleAttestation.Attestation memory a = _attestation(id, first, true);
        bytes memory sig = _sign(a, signerKey);
        vm.warp(block.timestamp + 1 days);
        vm.roll(block.number + 100);
        AskRef memory second = _challenge(bob, id);
        // The old answer arrives while the new ask is live: it is not the round's question.
        vm.warp(a.issuedAt);
        assertTrue(_deliver(first, a, sig));
        assertEq(uint8(_phase(id, 1)), uint8(Facts.Phase.Asking));
        assertEq(c.getFact(id).verdict, 0);
        vm.warp(second.askedAt);
        assertTrue(_answer(id, second, false));
        assertEq(c.getFact(id).verdict, 2);
    }

    function test_failureOfAnOldAskDoesNotResumeTheNewOne() public {
        uint256 id = _create();
        AskRef memory first = _challenge(carol, id);
        vm.warp(block.timestamp + 1 days);
        _challenge(bob, id);
        assertTrue(intake.fail(first.requestId, 2, "timeout"));
        assertEq(uint8(_phase(id, 1)), uint8(Facts.Phase.Asking));
        assertFalse(c.trading(id));
    }

    function test_badAttestationsAreRefused() public {
        uint256 id = _create();
        AskRef memory ref = _challenge(carol, id);
        IOracleAttestation.Attestation memory a;

        a = _attestation(id, ref, true);
        _refused(ref, a, _sign(a, 0xB0B)); // wrong signer

        a = _attestation(id, ref, true);
        a.questionHash = keccak256("another question");
        _refused(ref, a, _sign(a, signerKey));

        a = _attestation(id, ref, true);
        a.panelSize = 4;
        a.quorum = 3;
        a.agreed = 4;
        _refused(ref, a, _sign(a, signerKey)); // weak panel

        a = _attestation(id, ref, true);
        a.agreed = 3;
        _refused(ref, a, _sign(a, signerKey)); // below quorum

        a = _attestation(id, ref, true);
        a.agreed = 6;
        _refused(ref, a, _sign(a, signerKey)); // more agreed than sat

        a = _attestation(id, ref, true);
        a.expiresAt = uint64(block.timestamp - 1);
        _refused(ref, a, _sign(a, signerKey));

        a = _attestation(id, ref, true);
        a.issuedAt = uint64(block.timestamp + 6 minutes);
        _refused(ref, a, _sign(a, signerKey));

        a = _attestation(id, ref, true);
        a.answer = abi.encode(uint256(2));
        _refused(ref, a, _sign(a, signerKey)); // not a bool

        a = _attestation(id, ref, true);
        a.answerType = 3;
        _refused(ref, a, _sign(a, signerKey));

        a = _attestation(id, ref, true);
        bytes memory sig = _sign(a, signerKey);
        a.figure = 1;
        _refused(ref, a, sig); // tampered after signing

        // Each refusal reverted, so the ask is still live and the round still waits for its answer.
        assertEq(uint8(_phase(id, 1)), uint8(Facts.Phase.Asking));
        assertTrue(_answer(id, ref, true));
        assertEq(c.getFact(id).verdict, 1);
    }

    function _refused(AskRef memory ref, IOracleAttestation.Attestation memory a, bytes memory sig) internal {
        vm.prank(address(intake));
        vm.expectRevert(Facts.BadAttestation.selector);
        c.onOracleResult(ref.requestId, a, sig);
    }

    function test_callbacksOnlyFromTheIntakeThatWasAsked() public {
        uint256 id = _create();
        AskRef memory ref = _challenge(carol, id);
        IOracleAttestation.Attestation memory a = _attestation(id, ref, true);
        bytes memory sig = _sign(a, signerKey);
        vm.expectRevert(Facts.UnknownAsk.selector);
        c.onOracleResult(ref.requestId, a, sig);
        vm.expectRevert(Facts.UnknownAsk.selector);
        c.onFailure(ref.requestId, 1, "x", 0, 0, "");
        MockIntake other = new MockIntake();
        vm.prank(address(other));
        vm.expectRevert(Facts.UnknownAsk.selector);
        c.onOracleResult(ref.requestId, a, sig);
    }

    function test_answerReplayIsRefused() public {
        uint256 id = _create();
        AskRef memory ref = _challenge(carol, id);
        IOracleAttestation.Attestation memory a = _attestation(id, ref, true);
        bytes memory sig = _sign(a, signerKey);
        assertTrue(_deliver(ref, a, sig));
        vm.prank(address(intake));
        vm.expectRevert(Facts.UnknownAsk.selector);
        c.onOracleResult(ref.requestId, a, sig);
    }

    function test_erc1271SignerRegistry() public {
        MockSignerRegistry registry = new MockSignerRegistry();
        registry.set(signer, true);
        Facts.OracleConfig memory config = Facts.OracleConfig({
            intake: IIntake(address(intake)),
            signer: address(registry),
            price: 0.5 ether,
            panelSize: 5,
            quorum: 4,
            action: bytes32("oracle.request@oracle-1")
        });
        vm.prank(owner);
        c.proposeOracleConfig(config);
        vm.warp(block.timestamp + 3 days);
        vm.prank(owner);
        c.activateOracleConfig();
        uint256 id = _create();
        assertEq(c.getRound(id, 1).configId, 1);
        _judge(id, true);
        assertEq(c.getFact(id).verdict, 1);
    }

    function test_callbackFitsTheIntakeGasLimit() public {
        uint256 id = _create();
        _buy(alice, id, 0, 1 ether);
        AskRef memory ref = _challenge(carol, id);
        IOracleAttestation.Attestation memory a = _attestation(id, ref, true);
        bytes memory sig = _sign(a, signerKey);
        vm.prank(address(intake));
        uint256 gasBefore = gasleft();
        c.onOracleResult(ref.requestId, a, sig);
        uint256 used = gasBefore - gasleft();
        assertLt(used, 150_000, "callback under the Intake's 200,000 with room");
    }

    // ---- rounds ----------------------------------------------------------------------------------------------------

    function test_openRound_afterAVerdictStartsFresh() public {
        uint256 id = _create();
        uint256 k = _buy(alice, id, 0, 3 ether);
        _judge(id, true);

        vm.prank(alice);
        vm.expectRevert(Facts.NotTrading.selector);
        c.buy(id, 0, 1 ether, 0);

        uint256 before = imd.balanceOf(bob);
        vm.prank(bob);
        assertEq(c.openRound(id), 2);
        Facts.Round memory r = c.getRound(id, 2);
        assertEq(r.seeder, bob);
        assertEq(before - imd.balanceOf(bob), r.seed);
        uint256[2] memory p = c.prices(id, 2);
        assertApproxEqAbs(p[0], 0.5 ether, 2);
        assertEq(c.getFact(id).verdict, 1, "the verdict stands until the next one");

        uint256 k2 = _buy(alice, id, 1, 1 ether);
        assertEq(c.sharesOf(id, 2, alice)[1], k2);
        // Round 1 still redeems.
        vm.prank(alice);
        assertEq(c.redeem(id, 1), k);
        // Fees in round 2 go to its seeder.
        assertGt(c.owed(bob), 0);

        _judge(id, false);
        assertEq(c.getFact(id).verdict, 2);
        vm.prank(alice);
        assertEq(c.redeem(id, 2), k2);
        _drain();
    }

    function test_openRound_refusedWhileARoundIsLive() public {
        uint256 id = _create();
        vm.prank(bob);
        vm.expectRevert(Facts.RoundStillOpen.selector);
        c.openRound(id);
        _challenge(carol, id);
        vm.prank(bob);
        vm.expectRevert(Facts.RoundStillOpen.selector);
        c.openRound(id);
    }

    function test_closeRound_onlyTheSeederAndOnlyWhenEmpty() public {
        uint256 id = _create();
        uint256 k = _buy(alice, id, 0, 1 ether);
        vm.prank(alice);
        vm.expectRevert(Facts.NotSeeder.selector);
        c.closeRound(id);
        vm.prank(creator);
        vm.expectRevert(Facts.StillHeld.selector);
        c.closeRound(id);

        vm.prank(alice);
        c.sell(id, 0, k, 0);
        uint256 before = imd.balanceOf(creator);
        vm.prank(creator);
        uint256 refund = c.closeRound(id);
        assertGe(refund, c.getRound(id, 1).seed, "the seed and the rounding come back");
        assertEq(imd.balanceOf(creator) - before, refund);
        assertEq(uint8(_phase(id, 1)), uint8(Facts.Phase.Closed));
        assertFalse(c.trading(id));

        vm.prank(bob);
        assertEq(c.openRound(id), 2);
        _drain();
    }

    function test_closeRound_refusedWhileAsking() public {
        uint256 id = _create();
        _challenge(carol, id);
        vm.prank(creator);
        vm.expectRevert(Facts.NotTrading.selector);
        c.closeRound(id);
    }

    // ---- owner -----------------------------------------------------------------------------------------------------

    function test_owner_configRotationAppliesToNewRoundsOnly() public {
        uint256 id = _create();
        MockIntake second = new MockIntake();
        Facts.OracleConfig memory config = Facts.OracleConfig({
            intake: IIntake(address(second)),
            signer: signer,
            price: 0.5 ether,
            panelSize: 7,
            quorum: 5,
            action: bytes32("oracle.request@oracle-1")
        });
        vm.prank(alice);
        vm.expectRevert();
        c.proposeOracleConfig(config);
        vm.startPrank(owner);
        c.proposeOracleConfig(config);
        vm.expectRevert(Facts.TooEarly.selector);
        c.activateOracleConfig();
        vm.warp(block.timestamp + 3 days);
        c.activateOracleConfig();
        vm.stopPrank();
        assertEq(c.configCount(), 2);
        assertEq(address(c.oracleConfig().intake), address(second));

        // Round 1 asks the first intake.
        AskRef memory ref = _challenge(carol, id);
        assertEq(intake.count(), 1);
        assertTrue(_answer(id, ref, true));

        vm.prank(bob);
        c.openRound(id);
        assertEq(c.getRound(id, 2).configId, 1);
        vm.prank(carol);
        c.challenge(id, 1 ether);
        assertEq(second.count(), 1);
        assertEq(vm.parseJsonUint(string(second.bodyOf(second.requestIds(0))), ".panelSize"), 7);
    }

    function test_owner_configProposalLapses() public {
        Facts.OracleConfig memory config = c.oracleConfig();
        vm.startPrank(owner);
        c.proposeOracleConfig(config);
        vm.warp(block.timestamp + 10 days + 1);
        vm.expectRevert(Facts.ConfigExpired.selector);
        c.activateOracleConfig();
        vm.stopPrank();
    }

    function test_owner_feeRecipient() public {
        vm.prank(alice);
        vm.expectRevert();
        c.setFeeRecipient(alice);
        vm.prank(owner);
        vm.expectRevert(Facts.ZeroAddress.selector);
        c.setFeeRecipient(address(0));
        vm.prank(owner);
        c.setFeeRecipient(alice);
        assertEq(c.feeRecipient(), alice);
    }

    // ---- blocked transfers -----------------------------------------------------------------------------------------

    function test_aBlockedBurnAddressDoesNotBlockTrades() public {
        uint256 id = _create();
        imd.setBlocked(DEAD, true);
        _buy(alice, id, 0, 1 ether);
        assertGt(c.owed(DEAD), 0);
    }

    // ---- conservation ----------------------------------------------------------------------------------------------

    /// @dev Random trades by three accounts, a verdict, every redemption and withdrawal: everything owed is paid
    ///      and the contract is left with at most rounding dust.
    /// forge-config: default.fuzz.runs = 512
    function testFuzz_conservation(uint256 seed, bool verdict, uint8 steps, uint64 b) public {
        uint256 liquidity = bound(b, 0.1 ether, 100 ether);
        vm.prank(creator);
        uint256 id = c.createFact(TOPIC, CLAIM, RULES, liquidity);
        address[3] memory traders = [alice, bob, carol];
        uint256 n = bound(steps, 1, 30);
        for (uint256 i; i < n; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            address who = traders[r % 3];
            uint8 side = uint8((r >> 8) % 2);
            if ((r >> 16) % 3 == 0) {
                uint256 held = c.sharesOf(id, 1, who)[side];
                if (held == 0) continue;
                uint256 amount = bound(r >> 24, 1, held);
                vm.prank(who);
                try c.sell(id, side, amount, 0) {} catch {}
            } else {
                uint256 amount = bound(r >> 24, 1e15, 20 * liquidity);
                vm.prank(who);
                try c.buy(id, side, amount, 0) {} catch {}
            }
            Facts.Round memory rd = c.getRound(id, 1);
            assertGe(rd.makerBalance, uint256(rd.q[0] > rd.q[1] ? rd.q[0] : rd.q[1]), "maker covers every side");
        }
        _judge(id, verdict);
        for (uint256 i; i < 3; ++i) {
            vm.prank(traders[i]);
            c.redeem(id, 1);
        }
        _drain();
    }

    /// @dev Withdraws everything owed and checks that only dust is left.
    function _drain() internal {
        address[5] memory who = [creator, alice, bob, carol, builder];
        for (uint256 i; i < who.length; ++i) {
            if (c.owed(who[i]) > 0) {
                vm.prank(who[i]);
                c.withdrawOwed();
            }
        }
        // Every round's unredeemed winners are still owed their shares.
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
}
