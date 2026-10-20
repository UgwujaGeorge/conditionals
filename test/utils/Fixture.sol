// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Conditionals} from "../../src/Conditionals.sol";
import {IIntake} from "../../src/interfaces/IIntake.sol";
import {IOracleAttestation} from "../../src/interfaces/IOracleAttestation.sol";
import {MockIMD, MockIntake} from "./Mocks.sol";

abstract contract Fixture is Test {
    MockIMD internal imd;
    MockIntake internal intake;
    Conditionals internal c;

    uint256 internal signerKey = 0xA11CE;
    address internal signer;
    address internal owner = makeAddr("owner");
    address internal builder = makeAddr("builder");
    address internal creator = makeAddr("creator");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");

    address internal constant DEAD = 0x000000000000000000000000000000000000dEaD;

    string internal constant CONDITION = "The Clarity Act is signed into US law";
    string internal constant OUTCOME = "ETH closes above 5000 USD on Coinbase on 2026-12-01";
    string internal constant RULES = "Use congress.gov for the law and the Coinbase ETH-USD daily close for the price.";

    uint64 internal closeTime;
    uint64 internal resolveTime;

    function setUp() public virtual {
        vm.warp(1_790_000_000);
        vm.roll(26_000_000);
        signer = vm.addr(signerKey);
        imd = new MockIMD();
        intake = new MockIntake();
        c = new Conditionals(owner, IERC20(address(imd)), IIntake(address(intake)), signer, builder);

        address[6] memory users = [creator, alice, bob, carol, dave, address(this)];
        for (uint256 i; i < users.length; ++i) {
            imd.mint(users[i], 1_000 ether);
            vm.prank(users[i]);
            imd.approve(address(c), type(uint256).max);
        }
        closeTime = uint64(block.timestamp + 7 days);
        resolveTime = uint64(block.timestamp + 14 days);
    }

    function _create() internal returns (uint256 id) {
        vm.prank(creator);
        id = c.createMarket(CONDITION, OUTCOME, RULES, closeTime, resolveTime, 1 ether);
    }

    function _stake(address who, uint256 id, uint8 world, uint8 side, uint256 amount) internal {
        vm.prank(who);
        c.stake(id, world, side, amount);
    }

    struct AskRef {
        bytes32 requestId;
        uint8 question;
        uint256 windowBlock;
    }

    /// @dev Warps to resolveTime and requests resolution; returns the asks in the order sent.
    function _request(uint256 id) internal returns (AskRef[] memory refs) {
        if (block.timestamp < resolveTime) vm.warp(resolveTime);
        uint256 before = intake.count();
        uint256 windowBlock = block.number - c.WINDOW_DEPTH();
        bool[2] memory wanted = [c.askable(id, 0), c.askable(id, 1)];
        c.requestResolution(id);
        uint256 n = intake.count() - before;
        refs = new AskRef[](n);
        uint256 k;
        for (uint8 q; q < 2; ++q) {
            if (wanted[q]) {
                refs[k] = AskRef(intake.requestIds(before + k), q, windowBlock);
                ++k;
            }
        }
    }

    function _attestation(uint256 id, AskRef memory ref, bool value)
        internal
        view
        returns (IOracleAttestation.Attestation memory a)
    {
        a.requestId = bytes32(bytes16(keccak256(abi.encode("oracle", ref.requestId))));
        a.chainId = 1;
        a.questionHash = keccak256(bytes(c.questionDocument(id, ref.question, ref.windowBlock)));
        a.answerType = 0;
        a.answer = abi.encode(value);
        a.figure = 0;
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

    function _deliver(bytes32 requestId, IOracleAttestation.Attestation memory a, bytes memory sig)
        internal
        returns (bool)
    {
        return intake.complete(requestId, abi.encode(a, sig));
    }

    function _answer(uint256 id, AskRef memory ref, bool value) internal returns (bool) {
        IOracleAttestation.Attestation memory a = _attestation(id, ref, value);
        return _deliver(ref.requestId, a, _sign(a, signerKey));
    }

    /// @dev The config the fixture deploys with, as a struct the owner could propose.
    function _config() internal view returns (Conditionals.OracleConfig memory) {
        return Conditionals.OracleConfig({
            intake: IIntake(address(intake)),
            signer: signer,
            price: 0.5 ether,
            panelSize: 5,
            quorum: 4,
            action: bytes32("oracle.request@oracle-1")
        });
    }

    /// @dev Requests and answers both questions.
    function _resolve(uint256 id, bool condition, bool outcome) internal {
        AskRef[] memory refs = _request(id);
        for (uint256 i; i < refs.length; ++i) {
            bool ok = _answer(id, refs[i], refs[i].question == 0 ? condition : outcome);
            assertTrue(ok, "answer not delivered");
        }
    }

    function _claim(address who, uint256 id) internal returns (uint256) {
        vm.prank(who);
        return c.claim(id);
    }
}
