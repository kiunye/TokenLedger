// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Script, console2} from "forge-std/Script.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";

/// @notice Self-contained load harness for the event-indexer exit criterion.
/// @dev Deploys a fresh TokenRegistry plus a foreign emitter on whatever chain
///      --rpc-url points at (local Anvil), whitelists ~10 actors plus the
///      owner and emits ~500 mixed events (mints/transfers/whitelist toggles)
///      in ONE broadcast run.
///
///      LOAD_PHASE env var splits emission for restart/outage tests:
///        unset or 0 → everything; 1 → whitelists+mints; 2 → toggles+transfers;
///        3 → deploy only, emit nothing (lets a test start the indexer first
///        and emit afterwards).
///      REGISTRY_ADDR env var (set for phase 2) reuses the phase-1 deployment
///      instead of deploying anew, so balances survive across the split.
///
///      Every call broadcasts from the owner key: the owner whitelists itself
///      and mints itself a balance so its 470 `transfer` calls are legal
///      (single-key broadcasts cannot sign for the derived actor addresses).
///      Machine-readable output lines (parsed by the ExUnit harness):
///        REGISTRY_ADDR=0x… FOREIGN_ADDR=0x… EXPECTED_EVENTS=<count>
contract LoadEvents is Script {
    uint256 constant MINT_AMOUNT = 1_000_000e18;
    uint256 constant TRANSFERS = 470;

    function run() external returns (TokenRegistry registry) {
        uint256 phase = vm.envOr("LOAD_PHASE", uint256(0));
        require(phase <= 3, "LOAD_PHASE must be 0, 1, 2, or 3");

        address existing = vm.envOr("REGISTRY_ADDR", address(0));
        bool fresh = existing == address(0);

        address[] memory actors = _actors();
        uint256 emitted;

        vm.startBroadcast();

        registry = fresh ? new TokenRegistry() : TokenRegistry(existing);
        ForeignEmitter foreign = new ForeignEmitter();

        // Same topic0, different emitting address: must never be indexed.
        // Emitted in phase 1 (and full runs) only.
        if (phase == 0 || phase == 1) {
            foreign.emitTransfers(25, msg.sender);
        }

        if (phase == 0 || phase == 1) {
            for (uint256 i = 0; i < actors.length; i++) {
                registry.setWhitelisted(actors[i], true); // 10 compliance events
                emitted++;
            }
            registry.setWhitelisted(msg.sender, true); // owner moves tokens below
            emitted++;

            for (uint256 i = 0; i < actors.length; i++) {
                registry.mint(actors[i], MINT_AMOUNT); // 10 mint transfers
                emitted++;
            }
            registry.mint(msg.sender, MINT_AMOUNT);
            emitted++;
        }

        if (phase == 0 || phase == 2) {
            for (uint256 i = 0; i < actors.length; i++) {
                // Redundant writes are emitted unconditionally by design.
                registry.setWhitelisted(actors[i], true); // 10 more compliance
                emitted++;
            }

            for (uint256 i = 0; i < TRANSFERS; i++) {
                address to = actors[i % actors.length];
                registry.transfer(to, ((i % 50) + 1) * 1e18); // 470 transfers
                emitted++;
            }
        }

        vm.stopBroadcast();

        console2.log("REGISTRY_ADDR=%s", address(registry));
        console2.log("FOREIGN_ADDR=%s", address(foreign));
        console2.log("EXPECTED_EVENTS=%d", emitted);

        // Read-back sanity on fresh deployments only: a reused registry's
        // supply depends on whatever earlier phases did to it.
        if (fresh) {
            uint256 expectedSupply =
                ((phase == 0 || phase == 1) ? actors.length + 1 : 0) * MINT_AMOUNT;
            require(registry.totalSupply() == expectedSupply, "load: supply mismatch");
        }
    }

    function _actors() internal view returns (address[] memory) {
        address[] memory actors = new address[](10);
        for (uint256 i = 0; i < actors.length; i++) {
            actors[i] = vm.addr(uint256(keccak256(abi.encode("token-ledger-actor", i))));
        }
        return actors;
    }
}

/// @notice Emits Transfer-shaped logs from an address the indexer does not
///         watch. Exists purely to prove fetch-side address filtering.
contract ForeignEmitter {
    event Transfer(address indexed from, address indexed to, uint256 amount);

    function emitTransfers(uint256 n, address subject) external {
        for (uint256 i = 0; i < n; i++) {
            emit Transfer(address(0), subject, i);
        }
    }
}
