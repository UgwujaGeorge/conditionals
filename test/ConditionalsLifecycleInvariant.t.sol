// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IIntake} from "../src/interfaces/IIntake.sol";
import {Conditionals} from "../src/Conditionals.sol";
import {IOracleAttestation} from "../src/interfaces/IOracleAttestation.sol";
import {Fixture} from "./utils/Fixture.sol";
import {MockIMD, MockIntake} from "./utils/Mocks.sol";

/// @dev Honest and hostile actors in one random sequence: traders, the oracle, a forger holding its own key or
///      replaying the oracle's answer to another question, and the owner rotating the signer and the fee recipient.
contract LifecycleHandler is Test {
    Conditionals internal c;
    MockIMD internal imd;
    MockIntake internal intake;
    address internal owner;

    uint256 internal constant KEY_A = 0xA11CE;
    uint256 internal constant KEY_B = 0xB0B2;
    uint256 internal constant FORGER = 0xBAD;

    address[4] public traders = [address(0xB1), address(0xB2), address(0xB3), address(0xB4)];
    address[2] public recipients;

    struct Req {
        bytes32 rid;
        uint256 marketId;
        uint8 question;
        uint256 windowBlock;
    }

    Req[] internal open;

    /// @dev Ghosts, per market.
    mapping(uint256 => uint256[4]) public deposited;
    mapping(uint256 => uint256) public claimedOf;
    mapping(uint256 => address) public signerAtCreation;
    mapping(uint256 => uint8) public finalStatus;
    mapping(uint256 => uint8[2]) internal seenAnswers;
    /// @dev stakeOf[market][trader][world][side].
    mapping(uint256 => uint256[2][2][4]) internal stakeOf;
    /// @dev What each third party has withdrawn from `owed`.
    mapping(address => uint256) public withdrawnOwed;

    bool public forgedAccepted;
    bool public voidPaidWrong;
    bool public reopened;
    bool public answerChanged;
    bool public winnerShortPaid;
    bool public owedPaidWrong;
    uint256 public forgeries;

    constructor(Conditionals c_, MockIMD imd_, MockIntake intake_, address owner_, address builder_) {
        c = c_;
        imd = imd_;
        intake = intake_;
        owner = owner_;
        recipients = [builder_, address(0xFEE2)];
        for (uint256 i; i < 4; ++i) {
            imd.mint(traders[i], 1e30);
            vm.prank(traders[i]);
            imd.approve(address(c), type(uint256).max);
        }
        imd.mint(address(this), 1e30);
        imd.approve(address(c), type(uint256).max);
    }

    function create(uint32 closeIn, uint32 extra) external {
        if (c.marketCount() >= 12) return;
        uint64 close = uint64(block.timestamp + bound(closeIn, 1, 5 days));
        uint64 resolve = uint64(close + bound(extra, 0, 5 days));
        uint256 id =
            c.createMarket("It rains in Paris", "The Seine floods", "Use Meteo France.", close, resolve, 10 ether);
        signerAtCreation[id] = c.getMarket(id).oracle.signer;
        _observe();
    }

    function stake(uint256 marketSeed, uint256 traderSeed, uint8 world, uint8 side, uint96 amount) external {
        uint256 id = _id(marketSeed);
        if (id == 0) return;
        Conditionals.Market memory m = c.getMarket(id);
        if (m.status != Conditionals.Status.Open || block.timestamp >= m.closeTime) return;
        uint256 a = bound(amount, 1e15, 500 ether);
        uint256 t = traderSeed % 4;
        vm.prank(traders[t]);
        c.stake(id, world % 2, side % 2, a);
        deposited[id][t] += a;
        stakeOf[id][t][world % 2][side % 2] += a;
        _observe();
    }

    function request(uint256 marketSeed) external {
        uint256 id = _id(marketSeed);
        if (id == 0 || (!c.askable(id, 0) && !c.askable(id, 1))) return;
        bool[2] memory wanted = [c.askable(id, 0), c.askable(id, 1)];
        uint256 before = intake.count();
        c.requestResolution(id);
        uint256 k;
        for (uint8 q; q < 2; ++q) {
            if (!wanted[q]) continue;
            open.push(Req(intake.requestIds(before + k), id, q, block.number - c.WINDOW_DEPTH()));
            ++k;
        }
        _observe();
    }

    function answer(uint256 seed, bool value) external {
        if (open.length == 0) return;
        Req memory r = _take(seed);
        IOracleAttestation.Attestation memory a = _attestation(r, r.question, value);
        intake.complete(r.rid, abi.encode(a, _sign(a, _keyOf(c.getMarket(r.marketId).oracle.signer))));
        _observe();
    }

    /// @dev A signature from a key that is not the market's, or the market's own signer answering the other question.
    function forge(uint256 seed, bool value, bool ownKey) external {
        if (open.length == 0) return;
        Req memory r = open[seed % open.length];
        uint8 before = c.getMarket(r.marketId).answers[r.question];
        IOracleAttestation.Attestation memory a;
        bytes memory sig;
        if (ownKey) {
            a = _attestation(r, r.question, value);
            sig = _sign(a, FORGER);
        } else {
            a = _attestation(r, 1 - r.question, value);
            sig = _sign(a, _keyOf(c.getMarket(r.marketId).oracle.signer));
        }
        ++forgeries;
        bool ok = intake.deliverRaw(address(c), abi.encodeCall(c.onOracleResult, (r.rid, a, sig)));
        if (ok && c.getMarket(r.marketId).answers[r.question] != before) forgedAccepted = true;
        _observe();
    }

    function failAsk(uint256 seed) external {
        if (open.length == 0) return;
        Req memory r = _take(seed);
        intake.fail(r.rid, 1, "body_refused");
        _observe();
    }

    function settleOrVoid(uint256 marketSeed) external {
        uint256 id = _id(marketSeed);
        if (id == 0) return;
        if (c.settleable(id)) c.settle(id);
        else if (c.voidable(id)) c.voidMarket(id);
        _observe();
    }

    function claim(uint256 marketSeed, uint256 traderSeed) external {
        uint256 id = _id(marketSeed);
        if (id == 0) return;
        uint256 t = traderSeed % 4;
        uint256 amount = c.claimable(id, traders[t]);
        if (amount == 0) return;
        vm.prank(traders[t]);
        uint256 got = c.claim(id);
        Conditionals.Market memory m = c.getMarket(id);
        if (m.status == Conditionals.Status.Voided && got != deposited[id][t]) voidPaidWrong = true;
        if (m.status == Conditionals.Status.Settled) {
            // At least: the other world in full, and in the world that happened the whole stake if refunded, else
            // the winning side's stake (the fee is capped at the losing pool, so a winner never nets a loss).
            uint256[2][2] memory s = stakeOf[id][t];
            uint256 floor = s[1 - m.world][0] + s[1 - m.world][1];
            floor += m.worldRefunded ? s[m.world][0] + s[m.world][1] : s[m.world][m.winningSide];
            if (got < floor) winnerShortPaid = true;
        }
        claimedOf[id] += got;
        _observe();
    }

    function rotateSigner(bool toB) external {
        Conditionals.OracleConfig memory cfg = Conditionals.OracleConfig({
            intake: IIntake(address(intake)),
            signer: vm.addr(toB ? KEY_B : KEY_A),
            price: 0.5 ether,
            panelSize: 5,
            quorum: 4,
            action: bytes32("oracle.request@oracle-1")
        });
        vm.prank(owner);
        c.proposeOracleConfig(cfg);
        _observe();
    }

    function activate() external {
        uint256 at = c.pendingOracleConfigAt();
        if (at == 0 || block.timestamp < at) return;
        vm.prank(owner);
        c.activateOracleConfig();
        _observe();
    }

    function setFeeRecipient(bool second) external {
        vm.prank(owner);
        c.setFeeRecipient(recipients[second ? 1 : 0]);
        _observe();
    }

    /// @dev IMD can refuse transfers to a blocked address; a blocked burn address or fee recipient must not stop
    ///      settlement, and what it was due waits in `owed`.
    function setBlocked(uint8 who, bool isBlocked) external {
        address a = _third(who);
        imd.setBlocked(a, isBlocked);
        _observe();
    }

    function withdrawOwed(uint8 who) external {
        address a = _third(who);
        uint256 due = c.owed(a);
        if (due == 0 || imd.blocked(a)) return;
        uint256 before = imd.balanceOf(a);
        vm.prank(a);
        uint256 got = c.withdrawOwed();
        if (got != due || imd.balanceOf(a) - before != due || c.owed(a) != 0) owedPaidWrong = true;
        withdrawnOwed[a] += got;
        _observe();
    }

    function warp(uint32 by) external {
        vm.warp(block.timestamp + bound(by, 1, 4 days));
        vm.roll(block.number + bound(by, 1, 1000));
        _observe();
    }

    // ---------------------------------------------------------------------------------------------------------------

    function _observe() internal {
        uint256 n = c.marketCount();
        for (uint256 id = 1; id <= n; ++id) {
            Conditionals.Market memory m = c.getMarket(id);
            uint8 s = uint8(m.status);
            if (finalStatus[id] != 0 && s != finalStatus[id]) reopened = true;
            if (s != 0) finalStatus[id] = s;
            for (uint256 q; q < 2; ++q) {
                if (seenAnswers[id][q] != 0 && m.answers[q] != seenAnswers[id][q]) answerChanged = true;
                if (m.answers[q] != 0) seenAnswers[id][q] = m.answers[q];
            }
        }
    }

    function _third(uint8 who) internal view returns (address) {
        uint8 i = who % 3;
        return i == 2 ? address(0x000000000000000000000000000000000000dEaD) : recipients[i];
    }

    function _id(uint256 seed) internal view returns (uint256) {
        uint256 n = c.marketCount();
        return n == 0 ? 0 : bound(seed, 1, n);
    }

    function _take(uint256 seed) internal returns (Req memory r) {
        uint256 i = seed % open.length;
        r = open[i];
        open[i] = open[open.length - 1];
        open.pop();
    }

    function _keyOf(address s) internal pure returns (uint256) {
        return s == vm.addr(KEY_B) ? KEY_B : KEY_A;
    }

    function _attestation(Req memory r, uint8 q, bool value)
        internal
        view
        returns (IOracleAttestation.Attestation memory a)
    {
        a.requestId = bytes32(bytes16(r.rid));
        a.chainId = 1;
        a.questionHash = keccak256(bytes(c.questionDocument(r.marketId, q, r.windowBlock)));
        a.answer = abi.encode(value);
        a.fromBlock = uint64(r.windowBlock);
        a.toBlock = uint64(r.windowBlock);
        a.panelSize = 5;
        a.quorum = 4;
        a.agreed = 4;
        a.issuedAt = uint64(block.timestamp);
        a.expiresAt = uint64(block.timestamp + 1 days);
    }

    function _sign(IOracleAttestation.Attestation memory a, uint256 key) internal view returns (bytes memory) {
        (uint8 v, bytes32 rr, bytes32 s) = vm.sign(key, c.attestationDigest(a));
        return abi.encodePacked(rr, s, v);
    }
}

contract ConditionalsLifecycleInvariantTest is Fixture {
    LifecycleHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new LifecycleHandler(c, imd, intake, owner, builder);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 80
    function invariant_forgedAnswersNeverCount() public view {
        assertFalse(handler.forgedAccepted());
    }

    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 80
    function invariant_finishedMarketsAndAnswersNeverChange() public view {
        assertFalse(handler.reopened(), "a settled or voided market changed status");
        assertFalse(handler.answerChanged(), "a stored answer changed");
        uint256 n = c.marketCount();
        for (uint256 id = 1; id <= n; ++id) {
            Conditionals.Market memory m = c.getMarket(id);
            assertEq(m.oracle.signer, handler.signerAtCreation(id), "a market's signer changed after creation");
            if (m.status != Conditionals.Status.Open) assertEq(m.budget, 0, "a finished market kept its budget");
        }
    }

    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 80
    function invariant_nobodyTakesMoreThanTheMarketHeld() public view {
        assertFalse(handler.voidPaidWrong(), "a voided market paid other than the stake");
        assertFalse(handler.winnerShortPaid(), "a settled market paid a trader less than its winning or refunded stake");
        assertFalse(handler.owedPaidWrong(), "withdrawOwed paid other than what was owed");
        uint256 n = c.marketCount();
        for (uint256 id = 1; id <= n; ++id) {
            uint256 total;
            for (uint256 t; t < 4; ++t) {
                total += handler.deposited(id, t);
            }
            assertLe(handler.claimedOf(id), total);
            Conditionals.Market memory m = c.getMarket(id);
            assertEq(m.pools[0][0] + m.pools[0][1] + m.pools[1][0] + m.pools[1][1], total);
        }
    }

    /// forge-config: default.invariant.runs = 128
    /// forge-config: default.invariant.depth = 80
    function invariant_solventAndNothingLeftApproved() public view {
        uint256 owed;
        uint256 n = c.marketCount();
        for (uint256 id = 1; id <= n; ++id) {
            Conditionals.Market memory m = c.getMarket(id);
            owed += m.budget;
            if (m.status == Conditionals.Status.Open) {
                owed += m.pools[0][0] + m.pools[0][1] + m.pools[1][0] + m.pools[1][1];
            } else {
                for (uint256 t; t < 4; ++t) {
                    owed += c.claimable(id, handler.traders(t));
                }
            }
        }
        address r0 = handler.recipients(0);
        address r1 = handler.recipients(1);
        owed += c.owed(DEAD) + c.owed(r0) + c.owed(r1);
        assertGe(imd.balanceOf(address(c)), owed);
        assertEq(imd.allowance(address(c), address(intake)), 0);
        // Every fee is either delivered or waiting in `owed`, never lost and never paid twice.
        assertEq(imd.balanceOf(DEAD) + c.owed(DEAD), c.totalBurned());
        assertEq(
            imd.balanceOf(r0) + imd.balanceOf(r1) + c.owed(r0) + c.owed(r1), c.totalBuilderFees(), "fees delivered"
        );
        // Uncapped, burned = pot*2% and fee = pot*1%, each rounded down: burned - 2*fee is 0 or 1. Capped at the
        // losing pool L, burned = floor(2L/3) and fee = L - burned: burned - 2*fee is 0, -1 or -2. So per market the
        // gap is within 2 wei of the 2:1 split.
        assertApproxEqAbs(c.totalBurned(), 2 * c.totalBuilderFees(), 2 * n);
    }
}
