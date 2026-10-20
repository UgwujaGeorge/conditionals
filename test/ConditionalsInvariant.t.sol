// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Conditionals} from "../src/Conditionals.sol";
import {IOracleAttestation} from "../src/interfaces/IOracleAttestation.sol";
import {Fixture} from "./utils/Fixture.sol";
import {MockIMD, MockIntake} from "./utils/Mocks.sol";

interface IAttestationSigner {
    function sign(IOracleAttestation.Attestation memory a) external view returns (bytes memory);
}

/// @dev Drives many markets through random stakes, asks, answers, failures, retries, voids and claims.
contract Handler is Test {
    Conditionals internal c;
    MockIMD internal imd;
    MockIntake internal intake;
    IAttestationSigner internal f;

    address[4] internal traders;
    bytes32[] internal openRequests;
    mapping(bytes32 => uint256) internal requestMarket;
    mapping(bytes32 => uint8) internal requestQuestion;
    mapping(bytes32 => uint256) internal requestBlock;

    /// @dev Ghost totals.
    uint256 public staked;
    uint256 public claimedTotal;
    uint256 public budgetsIn;
    uint256 public budgetsOut;

    constructor(Conditionals c_, MockIMD imd_, MockIntake intake_, IAttestationSigner f_) {
        c = c_;
        imd = imd_;
        intake = intake_;
        f = f_;
        traders = [address(0xA1), address(0xA2), address(0xA3), address(0xA4)];
        for (uint256 i; i < 4; ++i) {
            imd.mint(traders[i], 1e30);
            vm.prank(traders[i]);
            imd.approve(address(c), type(uint256).max);
        }
        imd.mint(address(this), 1e30);
        imd.approve(address(c), type(uint256).max);
    }

    function create(uint32 closeIn, uint32 extra) external {
        uint64 close = uint64(block.timestamp + bound(closeIn, 1, 10 days));
        uint64 resolve = uint64(close + bound(extra, 0, 10 days));
        c.createMarket("Condition happens", "Outcome happens", "Use public sources.", close, resolve, 1 ether);
        budgetsIn += 1 ether;
    }

    function stake(uint256 marketSeed, uint256 traderSeed, uint8 world, uint8 side, uint96 amount) external {
        if (c.marketCount() == 0) return;
        uint256 id = bound(marketSeed, 1, c.marketCount());
        Conditionals.Market memory m = c.getMarket(id);
        if (m.status != Conditionals.Status.Open || block.timestamp >= m.closeTime) return;
        uint256 a = bound(amount, 1e15, 1_000 ether);
        vm.prank(traders[traderSeed % 4]);
        c.stake(id, world % 2, side % 2, a);
        staked += a;
    }

    function request(uint256 marketSeed) external {
        if (c.marketCount() == 0) return;
        uint256 id = bound(marketSeed, 1, c.marketCount());
        if (!c.askable(id, 0) && !c.askable(id, 1)) return;
        bool[2] memory wanted = [c.askable(id, 0), c.askable(id, 1)];
        uint256 before = intake.count();
        uint256 budget = c.getMarket(id).budget;
        c.requestResolution(id);
        uint256 k;
        for (uint8 q; q < 2; ++q) {
            if (!wanted[q]) continue;
            bytes32 rid = intake.requestIds(before + k);
            ++k;
            openRequests.push(rid);
            requestMarket[rid] = id;
            requestQuestion[rid] = q;
            requestBlock[rid] = block.number - c.WINDOW_DEPTH();
        }
        uint256 spent = k * 0.5 ether;
        // Asks paid from the budget leave the contract; asks paid by the caller pass through.
        budgetsOut += spent < budget ? spent : budget;
    }

    function answer(uint256 requestSeed, bool value) external {
        if (openRequests.length == 0) return;
        uint256 i = requestSeed % openRequests.length;
        bytes32 rid = openRequests[i];
        openRequests[i] = openRequests[openRequests.length - 1];
        openRequests.pop();
        IOracleAttestation.Attestation memory a = _attestation(rid, value);
        intake.complete(rid, abi.encode(a, f.sign(a)));
    }

    function failAsk(uint256 requestSeed) external {
        if (openRequests.length == 0) return;
        uint256 i = requestSeed % openRequests.length;
        bytes32 rid = openRequests[i];
        openRequests[i] = openRequests[openRequests.length - 1];
        openRequests.pop();
        intake.fail(rid, 2, "disagreed");
    }

    function settleOrVoid(uint256 marketSeed) external {
        if (c.marketCount() == 0) return;
        uint256 id = bound(marketSeed, 1, c.marketCount());
        Conditionals.Market memory m = c.getMarket(id);
        if (m.status != Conditionals.Status.Open) return;
        if (c.settleable(id)) {
            c.settle(id);
            budgetsOut += m.budget;
        } else if (c.voidable(id)) {
            c.voidMarket(id);
            budgetsOut += m.budget;
        }
    }

    function claim(uint256 marketSeed, uint256 traderSeed) external {
        if (c.marketCount() == 0) return;
        uint256 id = bound(marketSeed, 1, c.marketCount());
        address t = traders[traderSeed % 4];
        uint256 amount = c.claimable(id, t);
        if (amount == 0) return;
        vm.prank(t);
        claimedTotal += c.claim(id);
    }

    function warp(uint32 by) external {
        vm.warp(block.timestamp + bound(by, 1, 5 days));
        vm.roll(block.number + bound(by, 1, 1000));
    }

    function _attestation(bytes32 rid, bool value) internal view returns (IOracleAttestation.Attestation memory a) {
        uint256 id = requestMarket[rid];
        uint8 q = requestQuestion[rid];
        uint256 b = requestBlock[rid];
        a.requestId = bytes32(bytes16(rid));
        a.chainId = 1;
        a.questionHash = keccak256(bytes(c.questionDocument(id, q, b)));
        a.answer = abi.encode(value);
        a.fromBlock = uint64(b);
        a.toBlock = uint64(b);
        a.panelSize = 5;
        a.quorum = 4;
        a.agreed = 4;
        a.issuedAt = uint64(block.timestamp);
        a.expiresAt = uint64(block.timestamp + 1 days);
    }
}

contract ConditionalsInvariantTest is Fixture {
    Handler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new Handler(c, imd, intake, IAttestationSigner(address(this)));
        targetContract(address(handler));
    }

    function sign(IOracleAttestation.Attestation memory a) external view returns (bytes memory) {
        return _sign(a, signerKey);
    }

    /// @dev The contract always holds at least what it still owes: every unclaimed stake's payout plus budgets.
    function invariant_solvent() public view {
        uint256 owed;
        uint256 n = c.marketCount();
        address[4] memory traders = [address(0xA1), address(0xA2), address(0xA3), address(0xA4)];
        for (uint256 id = 1; id <= n; ++id) {
            Conditionals.Market memory m = c.getMarket(id);
            owed += m.budget;
            if (m.status == Conditionals.Status.Open) {
                owed += m.pools[0][0] + m.pools[0][1] + m.pools[1][0] + m.pools[1][1];
            } else {
                for (uint256 t; t < 4; ++t) {
                    owed += c.claimable(id, traders[t]);
                }
            }
        }
        assertGe(imd.balanceOf(address(c)), owed);
    }

    /// @dev Money in equals money out plus what is held: nothing is created or lost.
    function invariant_conservation() public view {
        uint256 inflow = handler.staked() + handler.budgetsIn();
        uint256 outflow = handler.claimedTotal() + handler.budgetsOut() + c.totalBurned() + c.totalBuilderFees();
        assertEq(imd.balanceOf(address(c)), inflow - outflow);
    }

    /// @dev Fees are exactly 2% burned and 1% to the builder, never more than 3% of what was staked.
    function invariant_feesBounded() public view {
        assertLe(c.totalBurned() + c.totalBuilderFees(), handler.staked() * 3 / 100 + 1);
        assertEq(imd.balanceOf(DEAD), c.totalBurned());
        assertEq(imd.balanceOf(builder), c.totalBuilderFees());
    }
}
