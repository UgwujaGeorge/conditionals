// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The part of the IdentityMD Intake (version 2) a buyer calls.
/// @dev https://imd.fun/docs/#intake. Robinhood Chain: 0xa43e6f75ee006411f79ac1c84120606c2330de82.
interface IIntake {
    struct Callback {
        address target;
        bytes4 selector;
    }

    function requestWithFailure(
        bytes32 action,
        bytes calldata body,
        Callback calldata callback,
        bytes4 onFailure,
        address asset,
        uint256 amount
    ) external returns (bytes32 requestId);
}
