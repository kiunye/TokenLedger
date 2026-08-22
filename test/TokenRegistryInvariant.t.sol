// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";

/// @notice Handler for the supply-conservation invariant. Owns the registry it
///         deploys (so it can act as owner) and exposes three bounded actions —
///         mint, transfer, whitelist-toggle — over a fixed actor set.
/// @dev Ghost state (`ghostBalances`, `ghostSum`) mirrors the effects of every
///      successful action. Transfers execute as the acting actor via
///      vm.prank — the handler itself is owner and deliberately NOT
///      whitelisted (decision 5), so it must never move tokens in its own
///      name. Transfers revert only when actor or recipient is revoked;
///      those reverts propagate out of the handler (fail_on_revert defaults
///      to false) and change no state, so ghost updates are skipped exactly
///      when the chain skipped them.
contract TokenRegistryHandler is Test {
    TokenRegistry public registry;

    uint256 public constant ACTOR_COUNT = 3;
    uint256 public constant MAX_MINT = 1000e18;

    address[] public actors;
    mapping(address => uint256) public ghostBalances;
    uint256 public ghostSum;

    constructor() {
        registry = new TokenRegistry(); // handler is the owner
        for (uint256 i; i < ACTOR_COUNT; ++i) {
            actors.push(makeAddr(string.concat("actor", vm.toString(i))));
        }
    }

    /// @dev Mints to a bounded actor, whitelisting first if needed. Redundant
    ///      whitelist writes are expected and harmless (decision 8).
    function mint(uint256 actorSeed, uint256 amountSeed) external {
        address actor = actors[actorSeed % ACTOR_COUNT];
        if (!registry.whitelisted(actor)) {
            registry.setWhitelisted(actor, true);
        }
        uint256 amount = bound(amountSeed, 0, MAX_MINT);

        registry.mint(actor, amount);
        ghostBalances[actor] += amount;
        ghostSum += amount;
    }

    /// @dev Transfers between two bounded actors, sent as the acting actor.
    ///      Amount is capped at the sender's real balance, so InsufficientBalance
    ///      can never fire here (that path is covered by unit tests, not this
    ///      fuzz run). Whitelist reverts do occur — whenever the sender or
    ///      recipient has been revoked — and are left to propagate: they roll
    ///      back their own state changes, and execution never reaches the
    ///      ghost updates below.
    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = actors[fromSeed % ACTOR_COUNT];
        address to = actors[toSeed % ACTOR_COUNT];
        uint256 amount = bound(amountSeed, 0, registry.balanceOf(from));

        vm.prank(from);
        registry.transfer(to, amount);
        ghostBalances[from] -= amount;
        ghostBalances[to] += amount;
    }

    /// @dev Flips an actor's whitelist status. Balances are untouched by
    ///      design (freeze, not burn), so ghosts are unaffected.
    function toggleWhitelist(uint256 actorSeed) external {
        address actor = actors[actorSeed % ACTOR_COUNT];
        registry.setWhitelisted(actor, !registry.whitelisted(actor));
    }
}

/// @notice Supply conservation invariant (spec: Requirement "Supply
///         conservation invariant"): across arbitrary randomized sequences of
///         mints, transfers, and whitelist toggles, the sum of all balances
///         equals totalSupply after every action.
contract TokenRegistryInvariantTest is Test {
    TokenRegistryHandler internal handler;

    function setUp() public {
        handler = new TokenRegistryHandler();
        targetContract(address(handler));
    }

    /// Ghost aggregate must track totalSupply exactly.
    function invariant_GhostSumEqualsTotalSupply() public view {
        assertEq(handler.ghostSum(), handler.registry().totalSupply(), "ghostSum != totalSupply");
    }

    /// Each tracked balance must match the chain, and their recomputed sum
    /// must equal totalSupply — catches drift even if ghosts were wrong.
    function invariant_TrackedBalancesMatchChain_SumEqualsTotalSupply() public view {
        uint256 sum;
        for (uint256 i; i < handler.ACTOR_COUNT(); ++i) {
            address actor = handler.actors(i);
            uint256 onChain = handler.registry().balanceOf(actor);
            assertEq(onChain, handler.ghostBalances(actor), "mirror drift for actor");
            sum += onChain;
        }
        assertEq(sum, handler.registry().totalSupply(), "recomputed sum != totalSupply");
    }
}
