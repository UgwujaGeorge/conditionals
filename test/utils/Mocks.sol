// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IIntake} from "../../src/interfaces/IIntake.sol";
import {IOracleAttestation} from "../../src/interfaces/IOracleAttestation.sol";

/// @dev Plain OpenZeppelin ERC-20 like IMD: it reverts on transfers to the zero address.
contract MockIMD is ERC20 {
    constructor() ERC20("Identity.md", "IMD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Behaves like the Intake for a buyer: pulls the price, forwards it to the payee, records the ask and later
///      completes it by calling the callback with a 200,000 gas limit inside a try, as the writer does.
contract MockIntake is IIntake {
    struct Request {
        address payer;
        bytes32 action;
        bytes body;
        Callback callback;
        bytes4 onFailure;
        bool completed;
        bool delivered;
    }

    uint256 public constant PRICE = 0.5 ether;
    uint256 public constant CALLBACK_GAS = 200_000;
    address public constant PAYEE = address(0x4e0fA57Bde726079356537E2F34d671E9F41ADbc);

    uint256 public nonce;
    mapping(bytes32 => Request) public requests;
    bytes32[] public requestIds;

    function requestWithFailure(
        bytes32 action,
        bytes calldata body,
        Callback calldata callback,
        bytes4 onFailure,
        address asset,
        uint256 amount
    ) external returns (bytes32 requestId) {
        require(amount >= PRICE, "PriceNotMet");
        IERC20(asset).transferFrom(msg.sender, PAYEE, amount);
        requestId = keccak256(abi.encode(address(this), ++nonce));
        Request storage r = requests[requestId];
        r.payer = msg.sender;
        r.action = action;
        r.body = body;
        r.callback = callback;
        r.onFailure = onFailure;
        requestIds.push(requestId);
    }

    function count() external view returns (uint256) {
        return requestIds.length;
    }

    function bodyOf(bytes32 requestId) external view returns (bytes memory) {
        return requests[requestId].body;
    }

    /// @dev Completes with status 0: `attestationAndSignature` is abi.encode(Attestation, signature).
    function complete(bytes32 requestId, bytes calldata attestationAndSignature) external returns (bool delivered) {
        Request storage r = requests[requestId];
        require(!r.completed, "completed");
        r.completed = true;
        (IOracleAttestation.Attestation memory a, bytes memory signature) =
            abi.decode(attestationAndSignature, (IOracleAttestation.Attestation, bytes));
        (delivered,) = r.callback.target.call{gas: CALLBACK_GAS}(
            abi.encodeWithSelector(r.callback.selector, requestId, a, signature)
        );
        r.delivered = delivered;
    }

    function fail(bytes32 requestId, uint8 status, bytes32 reason) external returns (bool delivered) {
        Request storage r = requests[requestId];
        require(!r.completed, "completed");
        r.completed = true;
        (delivered,) = r.callback.target.call{gas: CALLBACK_GAS}(
            abi.encodeWithSelector(r.onFailure, requestId, status, reason, uint16(0), uint16(0), bytes(""))
        );
        r.delivered = delivered;
    }

    /// @dev Any caller can name any contract as a callback on the real Intake; this mimics a forged delivery path.
    function deliverRaw(address target, bytes calldata data) external returns (bool ok) {
        (ok,) = target.call{gas: CALLBACK_GAS}(data);
    }
}
