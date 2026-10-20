// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Conditionals} from "../src/Conditionals.sol";
import {IIntake} from "../src/interfaces/IIntake.sol";

/// @dev Runs against Robinhood Chain when FORK_ROBINHOOD=1: the real Intake takes the contract's oracle asks.
///      Skipped otherwise, so the suite needs no RPC.
contract ConditionalsForkTest is Test {
    IERC20 constant IMD = IERC20(0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127);
    IIntake constant INTAKE = IIntake(0xa43e6F75ee006411F79Ac1C84120606C2330DE82);
    address constant SIGNER = 0x5598Aa9146215Bc13eb26f2c692Ad1461Fd32982;
    address constant PAYEE = 0x4e0fA57Bde726079356537E2F34d671E9F41ADbc;

    event Requested(bytes32 indexed requestId);

    function test_fork_realIntakeAcceptsTheAsks() public {
        if (!vm.envOr("FORK_ROBINHOOD", false)) return;
        vm.createSelectFork("robinhood");
        assertGt(block.number, 26_000_000, "block.number is the Ethereum block number on Robinhood Chain");

        address creator = makeAddr("creator");
        Conditionals c = new Conditionals(address(this), IMD, INTAKE, SIGNER, address(this));
        deal(address(IMD), creator, 10 ether);
        vm.startPrank(creator);
        IMD.approve(address(c), type(uint256).max);
        uint256 id = c.createMarket(
            "The Clarity Act is signed into US law",
            "ETH closes above 5000 USD on Coinbase on 2026-12-01",
            "Use congress.gov for the law and the Coinbase ETH-USD daily close for the price.",
            uint64(block.timestamp + 1 hours),
            uint64(block.timestamp + 2 hours),
            1 ether
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);
        uint256 payeeBefore = IMD.balanceOf(PAYEE);
        vm.recordLogs();
        assertEq(c.requestResolution(id), 2);
        assertEq(IMD.balanceOf(PAYEE) - payeeBefore, 1 ether, "the Intake forwarded both payments");
        assertEq(IMD.balanceOf(address(c)), 0);
        assertEq(IMD.allowance(address(c), address(INTAKE)), 0);
        assertGt(vm.getRecordedLogs().length, 4);
        assertEq(c.getMarket(id).openAsks[0], 1);
        assertEq(c.getMarket(id).openAsks[1], 1);
    }
}
