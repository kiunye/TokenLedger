// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {TokenRegistry} from "../src/TokenRegistry.sol";

/// @notice Unit tests for TokenRegistry. Each spec scenario in
///         openspec/changes/add-token-registry-contract/specs/token-registry/spec.md
///         maps to at least one test here; revert paths are asserted by exact
///         custom-error selector and happy paths by emitted events.
contract TokenRegistryTest is Test {
    TokenRegistry internal registry;

    address internal owner = makeAddr("owner");
    address internal investor = makeAddr("investor");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant AMOUNT = 100e18;

    function setUp() public {
        vm.prank(owner);
        registry = new TokenRegistry();
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------

    /// @dev Whitelist an account and mint to it, as the owner.
    function _whitelistAndMint(address account, uint256 amount) internal {
        vm.startPrank(owner);
        registry.setWhitelisted(account, true);
        registry.mint(account, amount);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------
    // Whitelist administration (spec: Requirement "Whitelist administration")
    // ------------------------------------------------------------------

    /// Scenario: Owner grants whitelist.
    function test_OwnerGrantsWhitelist_SetsStateAndEmits() public {
        vm.expectEmit(true, false, false, true);
        emit TokenRegistry.ComplianceUpdated(investor, true);
        vm.prank(owner);
        registry.setWhitelisted(investor, true);

        assertTrue(registry.whitelisted(investor), "investor should be whitelisted");
    }

    /// Scenario: Non-owner is rejected. State must be unchanged.
    function test_NonOwnerSetWhitelisted_RevertsNotOwner_StateUnchanged() public {
        vm.prank(alice);
        vm.expectRevert(TokenRegistry.NotOwner.selector);
        registry.setWhitelisted(bob, true);

        assertFalse(registry.whitelisted(bob), "whitelist state should be unchanged");
    }

    /// Scenario: Redundant write still emits.
    function test_RedundantWhitelistWrite_StillEmits() public {
        _whitelistAndMint(alice, 0);

        vm.expectEmit(true, false, false, true);
        emit TokenRegistry.ComplianceUpdated(alice, true);
        vm.prank(owner);
        registry.setWhitelisted(alice, true);

        assertTrue(registry.whitelisted(alice), "state should still be written");
    }

    /// Scenario: Zero address is rejected.
    function test_SetWhitelistedZeroAddress_RevertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TokenRegistry.ZeroAddress.selector);
        registry.setWhitelisted(address(0), true);
    }

    /// Extra edge: revocation also emits, with `false`.
    function test_RevokeWhitelist_EmitsComplianceUpdatedFalse() public {
        _whitelistAndMint(alice, 1);

        vm.expectEmit(true, false, false, true);
        emit TokenRegistry.ComplianceUpdated(alice, false);
        vm.prank(owner);
        registry.setWhitelisted(alice, false);

        assertFalse(registry.whitelisted(alice), "alice should be revoked");
    }

    // ------------------------------------------------------------------
    // Minting (spec: Requirement "Owner-only minting to whitelisted recipients")
    // ------------------------------------------------------------------

    /// Scenario: Mint to whitelisted recipient.
    function test_MintToWhitelisted_CreditsBalanceAndSupply_EmitsMintTransfer() public {
        vm.startPrank(owner);
        registry.setWhitelisted(investor, true);

        vm.expectEmit(true, true, false, true);
        emit TokenRegistry.Transfer(address(0), investor, AMOUNT);
        registry.mint(investor, AMOUNT);
        vm.stopPrank();

        assertEq(registry.balanceOf(investor), AMOUNT, "balance should increase by amount");
        assertEq(registry.totalSupply(), AMOUNT, "totalSupply should increase by amount");
    }

    /// Scenario: Mint to non-whitelisted recipient reverts even for owner;
    /// supply unchanged.
    function test_MintToNonWhitelisted_RevertsNotWhitelisted_EvenForOwner() public {
        assertEq(registry.totalSupply(), 0, "supply starts at zero");

        vm.prank(owner);
        vm.expectRevert(TokenRegistry.NotWhitelisted.selector);
        registry.mint(investor, AMOUNT);

        assertEq(registry.totalSupply(), 0, "supply should be unchanged");
        assertEq(registry.balanceOf(investor), 0, "balance should be unchanged");
    }

    /// Scenario: Non-owner cannot mint.
    function test_NonOwnerMint_RevertsNotOwner() public {
        vm.prank(owner);
        registry.setWhitelisted(alice, true);

        vm.prank(alice);
        vm.expectRevert(TokenRegistry.NotOwner.selector);
        registry.mint(alice, AMOUNT);
    }

    /// Scenario: Mint to zero address is rejected (regardless of whitelist
    /// status of the zero address).
    function test_MintToZeroAddress_RevertsZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TokenRegistry.ZeroAddress.selector);
        registry.mint(address(0), AMOUNT);
    }

    /// Extra edge (design decision 5): the owner holds no implicit whitelist;
    /// owner must whitelist self before minting to self.
    function test_OwnerNotImplicitlyWhitelisted_MustSelfWhitelistToReceive() public {
        vm.prank(owner);
        vm.expectRevert(TokenRegistry.NotWhitelisted.selector);
        registry.mint(owner, AMOUNT);

        vm.startPrank(owner);
        registry.setWhitelisted(owner, true);
        registry.mint(owner, AMOUNT);
        vm.stopPrank();

        assertEq(registry.balanceOf(owner), AMOUNT, "owner balance after self-mint");
    }

    // ------------------------------------------------------------------
    // Transfers (spec: Requirement "Transfers gated on both parties' whitelist status")
    // ------------------------------------------------------------------

    /// Scenario: Transfer between whitelisted addresses.
    function test_TransferBetweenWhitelisted_AdjustsBalancesAndEmits() public {
        uint256 sendAmount = 50e18;
        _whitelistAndMint(alice, AMOUNT);
        vm.prank(owner);
        registry.setWhitelisted(bob, true);

        vm.expectEmit(true, true, false, true);
        emit TokenRegistry.Transfer(alice, bob, sendAmount);
        vm.prank(alice);
        assertTrue(registry.transfer(bob, sendAmount), "transfer should return true");

        assertEq(registry.balanceOf(alice), AMOUNT - sendAmount, "sender debited");
        assertEq(registry.balanceOf(bob), sendAmount, "recipient credited");
        assertEq(registry.totalSupply(), AMOUNT, "supply conserved across transfer");
    }

    /// Scenario: Revoked sender is frozen; balance unchanged.
    function test_TransferByRevokedSender_RevertsNotWhitelisted_BalanceUnchanged() public {
        _whitelistAndMint(alice, AMOUNT);
        vm.prank(owner);
        registry.setWhitelisted(bob, true);
        vm.prank(owner);
        registry.setWhitelisted(alice, false);

        vm.prank(alice);
        vm.expectRevert(TokenRegistry.NotWhitelisted.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        registry.transfer(bob, 1);

        assertEq(registry.balanceOf(alice), AMOUNT, "frozen sender balance unchanged");
        assertEq(registry.balanceOf(bob), 0, "recipient received nothing");
    }

    /// Scenario: Non-whitelisted recipient is rejected; neither balance changes.
    function test_TransferToNonWhitelistedRecipient_RevertsNotWhitelisted_NoBalanceChange() public {
        _whitelistAndMint(alice, AMOUNT);

        vm.prank(alice);
        vm.expectRevert(TokenRegistry.NotWhitelisted.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        registry.transfer(bob, 50e18);

        assertEq(registry.balanceOf(alice), AMOUNT, "sender balance unchanged");
        assertEq(registry.balanceOf(bob), 0, "recipient balance unchanged");
    }

    /// Scenario: Insufficient balance is rejected.
    function test_TransferInsufficientBalance_RevertsInsufficientBalance() public {
        _whitelistAndMint(alice, AMOUNT);
        vm.prank(owner);
        registry.setWhitelisted(bob, true);

        vm.prank(alice);
        vm.expectRevert(TokenRegistry.InsufficientBalance.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        registry.transfer(bob, AMOUNT + 1);
    }

    /// Scenario: Transfer to zero address is rejected.
    function test_TransferToZeroAddress_RevertsZeroAddress() public {
        _whitelistAndMint(alice, AMOUNT);

        vm.prank(alice);
        vm.expectRevert(TokenRegistry.ZeroAddress.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        registry.transfer(address(0), 1);
    }

    // ------------------------------------------------------------------
    // Freeze semantics (spec: Requirement "Revocation freezes rather than burns")
    // ------------------------------------------------------------------

    /// Scenario: Balance survives revocation — and per the requirement text,
    /// the revoked address can neither send nor receive.
    function test_RevokedHolder_BalanceSurvives_CannotSendOrReceive_SupplyUnchanged() public {
        _whitelistAndMint(alice, AMOUNT);
        vm.prank(owner);
        registry.setWhitelisted(bob, true);

        vm.prank(owner);
        registry.setWhitelisted(alice, false);

        // Balance preserved exactly; no burn, no forced return.
        assertEq(registry.balanceOf(alice), AMOUNT, "revoked holder keeps exact balance");
        assertEq(registry.totalSupply(), AMOUNT, "totalSupply unchanged by revocation");

        // Cannot send...
        vm.prank(alice);
        vm.expectRevert(TokenRegistry.NotWhitelisted.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        registry.transfer(bob, 1);

        // ...and cannot receive.
        vm.prank(bob);
        vm.expectRevert(TokenRegistry.NotWhitelisted.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        registry.transfer(alice, 1);

        assertEq(registry.balanceOf(alice), AMOUNT, "balance still intact after attempts");
        assertEq(registry.totalSupply(), AMOUNT, "supply still unchanged");
    }

    // ------------------------------------------------------------------
    // Metadata (spec: Requirement "Token metadata and supply queries")
    // ------------------------------------------------------------------

    /// Scenario: Metadata values are readable.
    function test_Metadata_ReturnsConfiguredValues() public view {
        assertEq(registry.name(), "Token Ledger", "name");
        assertEq(registry.symbol(), "TLR", "symbol");
        assertEq(registry.decimals(), 18, "decimals");
    }

    // ------------------------------------------------------------------
    // Extra edges
    // ------------------------------------------------------------------

    /// Transferring the entire balance leaves a zero balance; supply conserved.
    function test_TransferEntireBalance_BalanceZero_SupplyConserved() public {
        _whitelistAndMint(alice, AMOUNT);
        vm.prank(owner);
        registry.setWhitelisted(bob, true);

        vm.prank(alice);
        assertTrue(registry.transfer(bob, AMOUNT), "full-balance transfer returns true");

        assertEq(registry.balanceOf(alice), 0, "sender fully drained");
        assertEq(registry.balanceOf(bob), AMOUNT, "recipient holds everything");
        assertEq(registry.totalSupply(), AMOUNT, "supply conserved");
    }

    /// Self-transfer conserves the sender's balance.
    function test_TransferToSelf_ConservesBalance() public {
        _whitelistAndMint(alice, AMOUNT);

        vm.prank(alice);
        assertTrue(registry.transfer(alice, AMOUNT), "self-transfer succeeds");

        assertEq(registry.balanceOf(alice), AMOUNT, "balance conserved on self-transfer");
        assertEq(registry.totalSupply(), AMOUNT, "supply conserved on self-transfer");
    }
}
