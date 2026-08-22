// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Script} from "forge-std/Script.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";

/// @notice Deploys TokenRegistry with the broadcasting account as owner,
///         whitelists the broadcaster, and asserts the bare initial state
///         (owner set, deployer whitelisted, zero supply) via read-back
///         checks that revert on failure.
contract Deploy is Script {
    function run() external returns (TokenRegistry registry) {
        vm.startBroadcast();

        registry = new TokenRegistry();
        address broadcaster = msg.sender;
        registry.setWhitelisted(broadcaster, true);

        // Read-back smoke assertions; any mismatch aborts the script.
        require(registry.owner() == broadcaster, "deploy: owner != broadcaster");
        require(registry.whitelisted(broadcaster), "deploy: broadcaster not whitelisted");
        require(registry.totalSupply() == 0, "deploy: totalSupply != 0");

        vm.stopBroadcast();
    }
}
