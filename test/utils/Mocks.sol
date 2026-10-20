// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IIntake} from "../../src/interfaces/IIntake.sol";
import {IOracleAttestation} from "../../src/interfaces/IOracleAttestation.sol";

/// @dev OpenZeppelin ERC-20 like IMD: it reverts on transfers to the zero address, and its owner can block an
///      address (the live IMD answers `blocked(address)`), which refuses transfers to or from it.
contract MockIMD is ERC20 {
    mapping(address => bool) public blocked;

    constructor() ERC20("Identity.md", "IMD") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setBlocked(address account, bool isBlocked) external {
        blocked[account] = isBlocked;
    }

    function _update(address from, address to, uint256 value) internal override {
        require(!blocked[from] && !blocked[to], "blocked");
        super._update(from, to, value);
    }
}

/// @dev A signer registry like the protocol's: answers ERC-1271 for the keys it lists.
contract MockSignerRegistry is IERC1271 {
    mapping(address => bool) public listed;

    function set(address key, bool ok) external {
        listed[key] = ok;
    }

    function isValidSignature(bytes32 hash, bytes memory signature) external view returns (bytes4) {
        (address recovered, ECDSA.RecoverError err,) = ECDSA.tryRecover(hash, signature);
        if (err == ECDSA.RecoverError.NoError && listed[recovered]) return IERC1271.isValidSignature.selector;
        return bytes4(0);
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

    uint256 public constant CALLBACK_GAS = 200_000;
    address public constant PAYEE = address(0x4e0fA57Bde726079356537E2F34d671E9F41ADbc);

    /// @dev The live price, owner-settable on the real Intake. Zero means not sold.
    uint256 public price = 0.5 ether;
    /// @dev Set to mimic an Intake without `priceOf` (a mock, or an older version): the call reverts.
    bool public priceOfReverts;

    uint256 public nonce;
    mapping(bytes32 => Request) public requests;
    bytes32[] public requestIds;

    function setPrice(uint256 price_) external {
        price = price_;
    }

    function setPriceOfReverts(bool reverts) external {
        priceOfReverts = reverts;
    }

    function priceOf(bytes32, address) external view returns (uint256) {
        require(!priceOfReverts, "no priceOf");
        return price;
    }

    function requestWithFailure(
        bytes32 action,
        bytes calldata body,
        Callback calldata callback,
        bytes4 onFailure,
        address asset,
        uint256 amount
    ) external returns (bytes32 requestId) {
        require(price != 0, "ActionNotSold");
        require(amount >= price, "PriceNotMet");
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
