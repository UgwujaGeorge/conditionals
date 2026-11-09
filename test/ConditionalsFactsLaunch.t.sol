// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ConditionalsFacts} from "../src/ConditionalsFacts.sol";
import {IIntake} from "../src/interfaces/IIntake.sol";

/// @dev Stands in for the launch factory: deploys the application by CREATE2, so its constructor runs with the factory
///      as `msg.sender` and nothing else on the chain.
contract FactsLaunchProbe {
    function deployAll(bytes[] memory codes, bytes32[] memory salts) external returns (address[] memory deployed) {
        deployed = new address[](codes.length);
        for (uint256 i; i < codes.length; ++i) {
            bytes memory code = codes[i];
            bytes32 salt = salts[i];
            address created;
            assembly ("memory-safe") {
                created := create2(0, add(code, 32), mload(code), salt)
            }
            require(created != address(0) && created.code.length > 0, "constructor failed");
            deployed[i] = created;
        }
    }
}

/// @dev Rehearses this `evm_contracts` launch as its floor does: ConditionalsFacts alone, deployed from its init code by
///      a factory on an empty chain with id 4663 and the brief's constructor arguments. No RPC: the IMD and Intake
///      addresses have no code here, which is why the constructor may not call them.
contract ConditionalsFactsLaunchTest is Test {
    address constant OWNER = 0x63BCf2d1483c7628d7D53704ff9c8199Dc28d907;
    address constant IMD = 0x5F7Bb59365ce557C26dbcAa4EE9d39A4b95B7127;
    address constant INTAKE = 0xa43e6F75ee006411F79Ac1C84120606C2330DE82;
    address constant SIGNER = 0x5598Aa9146215Bc13eb26f2c692Ad1461Fd32982;
    address constant FEE_RECIPIENT = 0x63BCf2d1483c7628d7D53704ff9c8199Dc28d907;

    FactsLaunchProbe factory;
    ConditionalsFacts c;

    function setUp() public {
        vm.chainId(4663);
        factory = new FactsLaunchProbe();
        assertEq(IMD.code.length, 0, "the rehearsal chain is empty");
        assertEq(INTAKE.code.length, 0);

        bytes32 salt = keccak256("ConditionalsFacts");
        bytes memory code = abi.encodePacked(
            type(ConditionalsFacts).creationCode, abi.encode(OWNER, IMD, INTAKE, SIGNER, FEE_RECIPIENT)
        );
        address predicted = vm.computeCreate2Address(salt, keccak256(code), address(factory));
        bytes[] memory codes = new bytes[](1);
        bytes32[] memory salts = new bytes32[](1);
        (codes[0], salts[0]) = (code, salt);
        address[] memory deployed = factory.deployAll(codes, salts);
        assertEq(deployed[0], predicted);
        c = ConditionalsFacts(deployed[0]);
    }

    function test_launch_constructorConfiguresEverything() public view {
        assertEq(block.chainid, 4663);
        assertEq(c.owner(), OWNER, "the owner is $owner, not the factory");
        assertTrue(c.owner() != address(factory));
        assertEq(c.pendingOwner(), address(0));
        assertEq(address(c.imd()), IMD);
        assertEq(c.feeRecipient(), FEE_RECIPIENT);
        ConditionalsFacts.OracleConfig memory config = c.oracleConfig();
        assertEq(address(config.intake), INTAKE);
        assertEq(config.signer, SIGNER);
        assertEq(config.price, 0.5 ether);
        assertEq(config.panelSize, 5);
        assertEq(config.quorum, 4);
        assertEq(config.action, bytes32("oracle.request@oracle-1"));
        assertEq(c.configCount(), 1);
        assertEq(c.pendingOracleConfigAt(), 0);
        assertEq(c.factCount(), 0);
        assertEq(c.WINDOW_DEPTH(), 10);
    }

    function test_launch_callbackSelectorsAreTheProtocolOnes() public pure {
        assertEq(ConditionalsFacts.onOracleResult.selector, bytes4(0x510379c7));
        assertEq(ConditionalsFacts.onFailure.selector, bytes4(0x5a0df71e));
    }

    /// @dev EIP-170 and the floor's opcode scan: no DELEGATECALL, CALLCODE or SELFDESTRUCT reachable in the runtime.
    function test_launch_runtimeFitsAndHasNoEscapeOpcodes() public view {
        bytes memory code = address(c).code;
        assertGt(code.length, 0, "missing runtime");
        assertLe(code.length, 24_576, "runtime exceeds EIP-170");
        bool reachable = true;
        for (uint256 j; j < code.length; ++j) {
            uint8 op = uint8(code[j]);
            if (op == 0x5b) reachable = true;
            if (op >= 0x60 && op <= 0x7f) {
                j += op - 0x5f;
                continue;
            }
            if (reachable) assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden application opcode");
            if (op == 0x00 || op == 0x56 || op == 0xf3 || op == 0xfd || op == 0xfe || op == 0xff) {
                reachable = false;
            }
        }
    }

    /// @dev A zero address is refused, so a mis-filled manifest cannot deploy.
    function test_launch_constructorRefusesZeroAddresses() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new ConditionalsFacts(address(0), IERC20(IMD), IIntake(INTAKE), SIGNER, FEE_RECIPIENT);
        vm.expectRevert(ConditionalsFacts.ZeroAddress.selector);
        new ConditionalsFacts(OWNER, IERC20(address(0)), IIntake(INTAKE), SIGNER, FEE_RECIPIENT);
        vm.expectRevert(ConditionalsFacts.ZeroAddress.selector);
        new ConditionalsFacts(OWNER, IERC20(IMD), IIntake(address(0)), SIGNER, FEE_RECIPIENT);
        vm.expectRevert(ConditionalsFacts.ZeroAddress.selector);
        new ConditionalsFacts(OWNER, IERC20(IMD), IIntake(INTAKE), address(0), FEE_RECIPIENT);
        vm.expectRevert(ConditionalsFacts.ZeroAddress.selector);
        new ConditionalsFacts(OWNER, IERC20(IMD), IIntake(INTAKE), SIGNER, address(0));
    }
}
