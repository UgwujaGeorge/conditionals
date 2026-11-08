// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ConditionalsFacts as Facts} from "../src/ConditionalsFacts.sol";
import {IIntake} from "../src/interfaces/IIntake.sol";
import {IOracleAttestation} from "../src/interfaces/IOracleAttestation.sol";
import {MockIMD, MockIntake} from "./utils/Mocks.sol";

/// @dev Two-outcome LMSR cost by Taylor series at 36 decimals, independent of Solady and of the maker's margins
///      (the two-outcome form of utils/LmsrReference.sol).
library Lmsr2Reference {
    uint256 internal constant ONE = 1e36;
    uint256 internal constant RAY = 1e27;

    function cost(int256[2] memory q, uint256 b) internal pure returns (int256) {
        int256 top = q[0] > q[1] ? q[0] : q[1];
        int256 low = q[0] > q[1] ? q[1] : q[0];
        uint256 x = uint256(top - low) * RAY / b;
        require(x <= 20 * RAY, "reference spread domain");
        uint256 term = ONE;
        uint256 exponential = ONE;
        for (uint256 n = 1; term != 0 && n < 256; ++n) {
            term = term * x / RAY / n;
            exponential += term;
        }
        require(term == 0, "reference exp convergence");
        uint256 sum = ONE + ONE * ONE / exponential;
        uint256 z = (sum - ONE) * ONE / (sum + ONE);
        uint256 zSquared = z * z / ONE;
        uint256 power = z;
        uint256 logarithm;
        for (uint256 odd = 1; power != 0 && odd < 513; odd += 2) {
            logarithm += power / odd;
            power = power * zSquared / ONE;
        }
        require(power == 0, "reference ln convergence");
        return top + int256(b * (2 * logarithm) / ONE);
    }
}

/// @dev Drives ConditionalsFacts in random order: trades, challenges, signed and forged answers, failures, timeouts,
///      closes, new rounds, redemptions, withdrawals, fee-recipient rotation and a burn address that refuses IMD.
///      Every call that should not fail but does is recorded with its revert data, and the invariants assert there
///      were none.
contract FactsHandler is Test {
    Facts public c;
    MockIMD public imd;
    MockIntake public intake;
    uint256 internal signerKey;
    address public owner;

    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    address[] public actors;
    address[] public recipients;
    uint256[] public factIds;

    struct AskRef {
        uint256 factId;
        uint32 round;
        bytes32 requestId;
        uint64 askedAt;
        uint256 windowBlock;
        bool completed;
    }

    AskRef[] public askRefs;

    /// @dev Rounds that reached Settled or Closed, and how: the phase and winner seen then.
    mapping(uint256 => mapping(uint32 => uint8)) public finishedPhase;
    mapping(uint256 => mapping(uint32 => uint8)) public finishedWinner;
    /// @dev Rounds a correctly signed answer was delivered to while they were waiting for it.
    mapping(uint256 => mapping(uint32 => bool)) public validAnswerSent;

    uint256 public unexpected;
    bytes public lastUnexpected;
    string public lastUnexpectedCall;
    uint256 public violations;
    string public lastViolation;

    uint256 public settledCount;
    uint256 public calls;

    constructor(Facts c_, MockIMD imd_, MockIntake intake_, uint256 signerKey_, address owner_, address builder_) {
        c = c_;
        imd = imd_;
        intake = intake_;
        signerKey = signerKey_;
        owner = owner_;
        for (uint256 i; i < 4; ++i) {
            address a = makeAddr(string.concat("factsActor", vm.toString(i)));
            actors.push(a);
            imd.mint(a, 1_000_000 ether);
            vm.prank(a);
            imd.approve(address(c), type(uint256).max);
        }
        recipients.push(builder_);
        recipients.push(makeAddr("builder2"));
        recipients.push(actors[0]);

        uint256[3] memory bs = [uint256(0.1 ether), 10 ether, 100 ether];
        for (uint256 i; i < 3; ++i) {
            vm.prank(actors[i]);
            factIds.push(
                c.createFact(
                    "Topic", string.concat("Claim number ", vm.toString(i), " holds"), "Judge by public sources.", bs[i]
                )
            );
        }
    }

    // ---- views for the invariants ---------------------------------------------------------------------------------

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function recipientCount() external view returns (uint256) {
        return recipients.length;
    }

    function factCount() external view returns (uint256) {
        return factIds.length;
    }

    function askCount() external view returns (uint256) {
        return askRefs.length;
    }

    // ---- helpers ---------------------------------------------------------------------------------------------------

    function _fact(uint256 sel) internal view returns (uint256 id, uint32 round, uint256 b) {
        id = factIds[sel % factIds.length];
        Facts.Fact memory f = c.getFact(id);
        round = f.rounds;
        b = f.b;
    }

    function _unexpected(string memory what, bytes memory err) internal {
        ++unexpected;
        lastUnexpected = err;
        lastUnexpectedCall = what;
    }

    function _violation(string memory what) internal {
        ++violations;
        lastViolation = what;
    }

    function _is(bytes memory err, bytes4 sel) internal pure returns (bool) {
        return err.length >= 4 && bytes4(err) == sel;
    }

    function _record(uint256 id, uint32 round) internal {
        Facts.Round memory r = c.getRound(id, round);
        if ((r.phase == Facts.Phase.Settled || r.phase == Facts.Phase.Closed) && finishedPhase[id][round] == 0) {
            finishedPhase[id][round] = uint8(r.phase);
            finishedWinner[id][round] = r.winner;
            if (r.phase == Facts.Phase.Settled) ++settledCount;
        }
    }

    function _attestation(AskRef memory ref, bool value)
        internal
        view
        returns (IOracleAttestation.Attestation memory a)
    {
        a.requestId = keccak256(abi.encode("oracle", ref.requestId));
        a.chainId = 1;
        a.questionHash = keccak256(bytes(c.questionDocument(ref.factId, ref.round, ref.askedAt, ref.windowBlock)));
        a.answerType = 0;
        a.answer = abi.encode(value);
        a.fromBlock = uint64(ref.windowBlock);
        a.toBlock = uint64(ref.windowBlock);
        a.panelSize = 5;
        a.quorum = 4;
        a.agreed = 4;
        a.issuedAt = uint64(block.timestamp);
        a.expiresAt = uint64(block.timestamp + 1 days);
    }

    function _sign(IOracleAttestation.Attestation memory a, uint256 key) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, c.attestationDigest(a));
        return abi.encodePacked(r, s, v);
    }

    // ---- actions ---------------------------------------------------------------------------------------------------

    function buy(uint256 who, uint256 factSel, uint8 side, uint256 amount) external {
        ++calls;
        (uint256 id, uint32 round, uint256 b) = _fact(factSel);
        if (!c.trading(id)) return;
        address a = actors[who % actors.length];
        amount = bound(amount, 1e15, 25 * b);
        side %= 2;
        uint256 before = imd.balanceOf(a);
        uint256 held = c.sharesOf(id, round, a)[side];
        vm.prank(a);
        try c.buy(id, side, amount, 0) returns (uint256 k) {
            if (before - imd.balanceOf(a) > amount) _violation("buy spent more than amount");
            if (c.sharesOf(id, round, a)[side] != held + k) _violation("buy did not credit shares");
            // Purchases, unlike sales, are held to MAX_SPREAD_B.
            int256[2] memory q = c.getRound(id, round).q;
            int256 gap = q[0] > q[1] ? q[0] - q[1] : q[1] - q[0];
            if (gap > 20 * int256(b)) _violation("a purchase left the spread beyond MAX_SPREAD_B");
        } catch (bytes memory err) {
            if (
                !_is(err, Facts.PriceLimit.selector) && !_is(err, Facts.TradeTooSmall.selector)
                    && !_is(err, Facts.TradeTooLarge.selector)
            ) _unexpected("buy", err);
        }
    }

    function buyFor(uint256 payer, uint256 who, uint256 factSel, uint8 side, uint256 amount) external {
        ++calls;
        (uint256 id, uint32 round, uint256 b) = _fact(factSel);
        if (!c.trading(id)) return;
        address p = actors[payer % actors.length];
        address a = actors[who % actors.length];
        amount = bound(amount, 1e15, 5 * b);
        side %= 2;
        uint256 held = c.sharesOf(id, round, a)[side];
        uint256 receiverBalance = imd.balanceOf(a);
        vm.prank(p);
        try c.buyFor(a, id, side, amount, 0) returns (uint256 k) {
            if (c.sharesOf(id, round, a)[side] != held + k) _violation("buyFor did not credit the account");
            if (p != a && imd.balanceOf(a) != receiverBalance) _violation("buyFor charged the account");
        } catch (bytes memory err) {
            if (
                !_is(err, Facts.PriceLimit.selector) && !_is(err, Facts.TradeTooSmall.selector)
                    && !_is(err, Facts.TradeTooLarge.selector)
            ) _unexpected("buyFor", err);
        }
    }

    function sell(uint256 who, uint256 factSel, uint8 side, uint256 shares, bool whole) external {
        ++calls;
        (uint256 id, uint32 round,) = _fact(factSel);
        if (!c.trading(id)) return;
        address a = actors[who % actors.length];
        side %= 2;
        uint256 held = c.sharesOf(id, round, a)[side];
        if (held == 0) return;
        shares = whole ? held : bound(shares, 1, held);
        uint256 before = imd.balanceOf(a);
        vm.prank(a);
        try c.sell(id, side, shares, 0) returns (uint256 proceeds) {
            if (imd.balanceOf(a) - before != proceeds) _violation("sell paid other than its proceeds");
            if (proceeds > shares) _violation("sell paid more than 1 IMD per share");
        } catch (bytes memory err) {
            // A partial sale below the minimum, or one worth less than the rounding, is refused. Sales are not held
            // to MAX_SPREAD_B (a sale only lowers C(q)); PriceLimit stays tolerated in case the implementation does.
            bool partialTooSmall = shares != held && _is(err, Facts.TradeTooSmall.selector);
            if (!partialTooSmall && !_is(err, Facts.PriceLimit.selector)) _unexpected("sell", err);
        }
    }

    function challenge(uint256 who, uint256 factSel) external {
        ++calls;
        (uint256 id, uint32 round,) = _fact(factSel);
        if (!c.trading(id)) return;
        address a = actors[who % actors.length];
        AskRef memory ref = AskRef(id, round, bytes32(0), uint64(block.timestamp), block.number - 10, false);
        vm.prank(a);
        try c.challenge(id, 10 ether) returns (bytes32 requestId) {
            ref.requestId = requestId;
            askRefs.push(ref);
            if (c.trading(id)) _violation("trading during a live ask");
        } catch (bytes memory err) {
            _unexpected("challenge", err);
        }
    }

    /// @dev Delivers a correctly signed answer the way the Intake does, under its 200,000 gas.
    function answer(uint256 askSel, bool value) external {
        ++calls;
        if (askRefs.length == 0) return;
        AskRef storage ref = askRefs[askSel % askRefs.length];
        if (ref.completed) return;
        ref.completed = true;
        Facts.Round memory r = c.getRound(ref.factId, ref.round);
        bytes32 key = keccak256(abi.encode(address(intake), ref.requestId));
        bool live = r.phase == Facts.Phase.Asking && r.askKey == key && block.timestamp < r.askedAt + 1 days;
        IOracleAttestation.Attestation memory a = _attestation(ref, value);
        bool delivered = intake.complete(ref.requestId, abi.encode(a, _sign(a, signerKey)));
        if (!delivered) _violation("a valid answer was not delivered under 200k gas");
        Facts.Round memory after_ = c.getRound(ref.factId, ref.round);
        if (live) {
            validAnswerSent[ref.factId][ref.round] = true;
            if (after_.phase != Facts.Phase.Settled) _violation("the live ask's valid answer did not settle");
            if (after_.winner != (value ? 0 : 1)) _violation("wrong winner");
        } else if (after_.phase != r.phase || after_.makerBalance != r.makerBalance) {
            _violation("a stale answer changed the round");
        }
        _record(ref.factId, ref.round);
    }

    /// @dev An answer signed by another key, or for another question, delivered for a pending ask: refused.
    function forgedAnswer(uint256 askSel, bool value, bool wrongQuestion) external {
        ++calls;
        if (askRefs.length == 0) return;
        AskRef memory ref = askRefs[askSel % askRefs.length];
        if (ref.completed) return;
        Facts.Round memory r = c.getRound(ref.factId, ref.round);
        // A stale ask is closed by any answer without verification (harmless: it settles nothing), so forged
        // answers are only tried against the live one, which must refuse them and stay answerable.
        bytes32 key = keccak256(abi.encode(address(intake), ref.requestId));
        if (r.phase != Facts.Phase.Asking || r.askKey != key || block.timestamp >= r.askedAt + 1 days) return;
        IOracleAttestation.Attestation memory a = _attestation(ref, value);
        bytes memory sig;
        if (wrongQuestion) {
            a.questionHash = keccak256(abi.encode("another question", a.questionHash));
            sig = _sign(a, signerKey);
        } else {
            sig = _sign(a, 0xB0B);
        }
        if (intake.deliverRaw(address(c), abi.encodeWithSelector(c.onOracleResult.selector, ref.requestId, a, sig))) {
            _violation("a forged answer was accepted");
        }
        Facts.Round memory after_ = c.getRound(ref.factId, ref.round);
        if (after_.phase != r.phase || after_.makerBalance != r.makerBalance) _violation("a forged answer moved");
    }

    function fail(uint256 askSel, uint8 status) external {
        ++calls;
        if (askRefs.length == 0) return;
        AskRef storage ref = askRefs[askSel % askRefs.length];
        if (ref.completed) return;
        ref.completed = true;
        Facts.Round memory r = c.getRound(ref.factId, ref.round);
        bytes32 key = keccak256(abi.encode(address(intake), ref.requestId));
        bool liveAsk = r.phase == Facts.Phase.Asking && r.askKey == key;
        if (!intake.fail(ref.requestId, 1 + status % 2, "disagreed")) _violation("failure not delivered");
        Facts.Round memory after_ = c.getRound(ref.factId, ref.round);
        if (liveAsk && after_.phase != Facts.Phase.Open) _violation("the live ask's failure did not resume");
        if (!liveAsk && after_.phase != r.phase) _violation("a stale failure changed the phase");
        if (after_.makerBalance != r.makerBalance) _violation("a failure moved funds");
    }

    function warp(uint256 secs) external {
        ++calls;
        secs = bound(secs, 1, 2 days);
        vm.warp(block.timestamp + secs);
        vm.roll(block.number + 1 + secs / 12);
    }

    function closeRound(uint256 factSel) external {
        ++calls;
        (uint256 id, uint32 round,) = _fact(factSel);
        Facts.Round memory r = c.getRound(id, round);
        if (!c.trading(id)) return;
        // Every share still held, of either side, stays in the maker at 1 IMD; the seeder takes the rest back or
        // pays in what the maker lacks.
        uint256 held = uint256(r.q[0]) + uint256(r.q[1]);
        uint256 before = imd.balanceOf(r.seeder);
        uint256 custody = imd.balanceOf(address(c));
        vm.prank(r.seeder);
        try c.closeRound(id) returns (uint256 refund) {
            uint256 expected = r.makerBalance > held ? r.makerBalance - held : 0;
            if (refund != expected) _violation("close refund");
            if (held > r.makerBalance) {
                if (before - imd.balanceOf(r.seeder) != held - r.makerBalance) _violation("close shortfall");
            } else if (imd.balanceOf(r.seeder) - before != refund) {
                _violation("close paid other than its refund");
            }
            if (held == 0 && refund < r.seed) _violation("an empty round returned less than its seed");
            if (c.getRound(id, round).makerBalance != held) _violation("closed maker != shares held");
            if (imd.balanceOf(address(c)) + refund != custody + (held > r.makerBalance ? held - r.makerBalance : 0)) {
                _violation("close moved other than the refund or shortfall");
            }
        } catch (bytes memory err) {
            _unexpected("closeRound", err);
        }
        _record(id, round);
    }

    function openRound(uint256 who, uint256 factSel) external {
        ++calls;
        (uint256 id, uint32 round,) = _fact(factSel);
        Facts.Phase phase = c.getRound(id, round).phase;
        if (phase != Facts.Phase.Settled && phase != Facts.Phase.Closed) return;
        vm.prank(actors[who % actors.length]);
        try c.openRound(id) returns (uint32 next) {
            if (next != round + 1) _violation("round numbering");
        } catch (bytes memory err) {
            _unexpected("openRound", err);
        }
    }

    function redeem(uint256 who, uint256 factSel, uint256 roundSel) external {
        ++calls;
        (uint256 id, uint32 rounds,) = _fact(factSel);
        uint32 round = uint32(bound(roundSel, 1, rounds));
        Facts.Round memory r = c.getRound(id, round);
        if (r.phase != Facts.Phase.Settled && r.phase != Facts.Phase.Closed) return;
        address a = actors[who % actors.length];
        uint256[2] memory s = c.sharesOf(id, round, a);
        // A settled round pays the winning side; a closed one pays every share of either side.
        uint256 expected = r.phase == Facts.Phase.Settled ? s[r.winner] : s[0] + s[1];
        uint256 before = imd.balanceOf(a);
        vm.prank(a);
        try c.redeem(id, round) returns (uint256 amount) {
            if (amount != expected || imd.balanceOf(a) - before != amount) _violation("redeem paid other than shares");
        } catch (bytes memory err) {
            _unexpected("redeem", err);
        }
    }

    function withdrawOwed(uint256 who) external {
        ++calls;
        address a = who % 5 == 4 ? recipients[who % recipients.length] : actors[who % actors.length];
        uint256 owed = c.owed(a);
        if (owed == 0) return;
        uint256 before = imd.balanceOf(a);
        vm.prank(a);
        try c.withdrawOwed() returns (uint256 amount) {
            if (amount != owed || imd.balanceOf(a) - before != owed || c.owed(a) != 0) _violation("withdraw");
        } catch (bytes memory err) {
            _unexpected("withdrawOwed", err);
        }
    }

    function setFeeRecipient(uint256 sel) external {
        ++calls;
        vm.prank(owner);
        c.setFeeRecipient(recipients[sel % recipients.length]);
    }

    function toggleBurnBlocked() external {
        ++calls;
        imd.setBlocked(DEAD, !imd.blocked(DEAD));
    }

    /// @dev Ends every round still live and pays out everything, for the end-of-run check.
    function settleAll() external {
        imd.setBlocked(DEAD, false);
        vm.warp(block.timestamp + 1 days + 1);
        vm.roll(block.number + 10_000);
        for (uint256 i; i < factIds.length; ++i) {
            uint256 id = factIds[i];
            uint32 round = c.getFact(id).rounds;
            if (c.trading(id)) {
                AskRef memory ref = AskRef(id, round, bytes32(0), uint64(block.timestamp), block.number - 10, true);
                vm.prank(actors[0]);
                ref.requestId = c.challenge(id, 10 ether);
                IOracleAttestation.Attestation memory a = _attestation(ref, i % 2 == 0);
                require(intake.complete(ref.requestId, abi.encode(a, _sign(a, signerKey))), "final answer");
                require(c.getRound(id, round).phase == Facts.Phase.Settled, "final settle");
            }
            for (uint32 r = 1; r <= round; ++r) {
                // Settled rounds pay their winners; closed rounds every share still held.
                Facts.Phase phase = c.getRound(id, r).phase;
                if (phase != Facts.Phase.Settled && phase != Facts.Phase.Closed) continue;
                for (uint256 j; j < actors.length; ++j) {
                    vm.prank(actors[j]);
                    c.redeem(id, r);
                }
            }
        }
        address[] memory all = new address[](actors.length + recipients.length + 1);
        for (uint256 j; j < actors.length; ++j) {
            all[j] = actors[j];
        }
        for (uint256 j; j < recipients.length; ++j) {
            all[actors.length + j] = recipients[j];
        }
        all[all.length - 1] = DEAD;
        for (uint256 j; j < all.length; ++j) {
            if (c.owed(all[j]) > 0) {
                vm.prank(all[j]);
                c.withdrawOwed();
            }
        }
    }
}

contract ConditionalsFactsInvariantTest is Test {
    Facts internal c;
    MockIMD internal imd;
    MockIntake internal intake;
    FactsHandler internal h;
    uint256 internal constant SIGNER_KEY = 0xA11CE;
    address internal owner = makeAddr("owner");
    address internal builder = makeAddr("builder");

    function setUp() public {
        vm.warp(1_790_000_000);
        vm.roll(26_000_000);
        imd = new MockIMD();
        intake = new MockIntake();
        c = new Facts(owner, IERC20(address(imd)), IIntake(address(intake)), vm.addr(SIGNER_KEY), builder);
        h = new FactsHandler(c, imd, intake, SIGNER_KEY, owner, builder);
        targetContract(address(h));
        bytes4[] memory selectors = new bytes4[](16);
        selectors[0] = FactsHandler.buy.selector;
        selectors[1] = FactsHandler.buy.selector;
        selectors[2] = FactsHandler.buyFor.selector;
        selectors[3] = FactsHandler.sell.selector;
        selectors[4] = FactsHandler.sell.selector;
        selectors[5] = FactsHandler.challenge.selector;
        selectors[6] = FactsHandler.answer.selector;
        selectors[7] = FactsHandler.forgedAnswer.selector;
        selectors[8] = FactsHandler.fail.selector;
        selectors[9] = FactsHandler.warp.selector;
        selectors[10] = FactsHandler.closeRound.selector;
        selectors[11] = FactsHandler.openRound.selector;
        selectors[12] = FactsHandler.redeem.selector;
        selectors[13] = FactsHandler.withdrawOwed.selector;
        selectors[14] = FactsHandler.setFeeRecipient.selector;
        selectors[15] = FactsHandler.toggleBurnBlocked.selector;
        targetSelector(FuzzSelector({addr: address(h), selectors: selectors}));
    }

    /// @dev Everything the contract holds is exactly what it owes: the makers' balances of every round plus every
    ///      account's `owed`. No rounding leaks in or out of this ledger.
    /// forge-config: default.invariant.runs = 256
    function invariant_custodyEqualsLiabilities() public view {
        uint256 liabilities;
        for (uint256 i; i < h.factCount(); ++i) {
            uint256 id = h.factIds(i);
            uint32 rounds = c.getFact(id).rounds;
            for (uint32 r = 1; r <= rounds; ++r) {
                liabilities += c.getRound(id, r).makerBalance;
            }
        }
        for (uint256 j; j < h.actorCount(); ++j) {
            liabilities += c.owed(h.actors(j));
        }
        for (uint256 j = 1; j < h.recipientCount() - 1; ++j) {
            liabilities += c.owed(h.recipients(j));
        }
        liabilities += c.owed(h.recipients(0));
        liabilities += c.owed(h.DEAD());
        assertEq(imd.balanceOf(address(c)), liabilities, "custody != makers + owed");
    }

    /// @dev Shares outstanding are exactly what the maker sold; a settled round's maker holds exactly the unredeemed
    ///      winning shares, a closed round's exactly every share still held; a live round's maker covers the true C(q), which
    ///      covers every side (past MAX_SPREAD_B, reachable only by sales, it covers the top side).
    /// forge-config: default.invariant.runs = 256
    function invariant_roundsAreSolventAndShareExact() public view {
        for (uint256 i; i < h.factCount(); ++i) {
            uint256 id = h.factIds(i);
            Facts.Fact memory f = c.getFact(id);
            for (uint32 r = 1; r <= f.rounds; ++r) {
                Facts.Round memory rd = c.getRound(id, r);
                uint256[2] memory held;
                for (uint256 j; j < h.actorCount(); ++j) {
                    uint256[2] memory s = c.sharesOf(id, r, h.actors(j));
                    held[0] += s[0];
                    held[1] += s[1];
                }
                assertGe(rd.q[0], 0, "negative q");
                assertGe(rd.q[1], 0, "negative q");
                if (r < f.rounds) {
                    assertTrue(
                        rd.phase == Facts.Phase.Settled || rd.phase == Facts.Phase.Closed, "an old round is still live"
                    );
                }
                if (rd.phase == Facts.Phase.Settled) {
                    assertEq(rd.makerBalance, held[rd.winner], "settled maker != unredeemed winners");
                    assertEq(rd.askKey, bytes32(0));
                } else if (rd.phase == Facts.Phase.Closed) {
                    // A closed round's maker holds exactly 1 IMD for every share still held, of either side.
                    assertEq(rd.makerBalance, held[0] + held[1], "closed maker != unredeemed shares");
                    assertEq(rd.askKey, bytes32(0));
                    assertLe(held[0], uint256(rd.q[0]));
                    assertLe(held[1], uint256(rd.q[1]));
                } else {
                    assertEq(uint256(rd.q[0]), held[0], "q[0] != shares held");
                    assertEq(uint256(rd.q[1]), held[1], "q[1] != shares held");
                }
                if (rd.phase == Facts.Phase.Open || rd.phase == Facts.Phase.Asking) {
                    int256 top = rd.q[0] > rd.q[1] ? rd.q[0] : rd.q[1];
                    int256 gap = rd.q[0] > rd.q[1] ? rd.q[0] - rd.q[1] : rd.q[1] - rd.q[0];
                    if (gap <= 20 * int256(f.b)) {
                        int256 cq = Lmsr2Reference.cost(rd.q, f.b);
                        assertGe(int256(rd.makerBalance), cq, "maker below C(q)");
                        assertGe(cq, top, "C(q) below a side");
                    } else {
                        // Only sales widen the spread past MAX_SPREAD_B. There C(q) - top = b ln(1 + e^(-gap/b)) is
                        // below b * 2.1e-9, outside the reference series' domain: the maker must still cover the top.
                        assertGe(int256(rd.makerBalance), top, "maker below the top side");
                    }
                }
            }
        }
    }

    /// @dev A finished round never reopens or changes its winner, and only a correctly signed answer to its live
    ///      ask settles a round.
    /// forge-config: default.invariant.runs = 256
    function invariant_finishedRoundsStayFinished() public view {
        for (uint256 i; i < h.factCount(); ++i) {
            uint256 id = h.factIds(i);
            uint32 rounds = c.getFact(id).rounds;
            for (uint32 r = 1; r <= rounds; ++r) {
                Facts.Round memory rd = c.getRound(id, r);
                uint8 seen = h.finishedPhase(id, r);
                if (seen != 0) {
                    assertEq(uint8(rd.phase), seen, "a finished round changed phase");
                    if (seen == uint8(Facts.Phase.Settled)) assertEq(rd.winner, h.finishedWinner(id, r));
                }
                if (rd.phase == Facts.Phase.Settled) {
                    assertTrue(h.validAnswerSent(id, r), "settled without a valid answer to its live ask");
                }
            }
        }
    }

    /// @dev Burned IMD is either at the burn address or owed to it; nothing else is lost.
    /// forge-config: default.invariant.runs = 256
    function invariant_burnAccounting() public view {
        assertEq(c.totalBurned(), imd.balanceOf(h.DEAD()) + c.owed(h.DEAD()), "burn ledger");
        assertEq(c.totalOracleSpend(), imd.balanceOf(intake.PAYEE()), "oracle spend ledger");
    }

    /// @dev No call the handler expected to succeed reverted, and no handler-side check failed.
    /// forge-config: default.invariant.runs = 256
    function invariant_noUnexpectedRevertsOrViolations() public view {
        assertEq(h.violations(), 0, h.lastViolation());
        assertEq(h.unexpected(), 0, string.concat(h.lastUnexpectedCall(), " ", vm.toString(h.lastUnexpected())));
    }

    /// @dev After any sequence: every live round can still be challenged and settled, every winner redeemed and every
    ///      debt withdrawn, leaving the contract with rounding dust only.
    function afterInvariant() public {
        h.settleAll();
        uint256 rounds;
        for (uint256 i; i < h.factCount(); ++i) {
            rounds += c.getFact(h.factIds(i)).rounds;
        }
        assertLe(imd.balanceOf(address(c)), rounds * 1e9, "more than rounding dust left after paying everyone");
    }
}
