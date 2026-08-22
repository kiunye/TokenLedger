// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

/// @title TokenRegistry
/// @notice Permissioned token registry: only whitelisted addresses may hold or
///         move tokens, enforced on both sides of every transfer. Revocation
///         freezes a balance in place rather than burning it. The owner alone
///         may mint and administer the whitelist, and holds no transfer
///         privileges beyond any other address.
/// @dev ERC-20-shaped surface minus allowance machinery (no approve/transferFrom).
///      Deliberately dependency-free. Event signatures (`Transfer`,
///      `ComplianceUpdated`) are locked by spec and consumed by the off-chain
///      indexer; treat any change to them as a breaking change.
contract TokenRegistry {
    // ------------------------------------------------------------------
    // Custom errors
    // ------------------------------------------------------------------

    /// @dev Caller is not the owner.
    error NotOwner();
    /// @dev An address involved in the operation is not whitelisted.
    error NotWhitelisted();
    /// @dev Sender's balance is less than the amount to transfer.
    error InsufficientBalance();
    /// @dev A recipient/administrated address was the zero address.
    error ZeroAddress();

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------

    /// @notice Emitted on transfers and mints. Minting uses `from = address(0)`.
    event Transfer(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted on every whitelist write, including redundant ones.
    event ComplianceUpdated(address indexed account, bool whitelisted);

    // ------------------------------------------------------------------
    // State
    // ------------------------------------------------------------------

    /// @notice Single administrator; set once in the constructor. No transfer mechanism.
    address public owner;
    /// @notice Permission flag deciding which addresses may hold or move tokens.
    mapping(address => bool) public whitelisted;
    /// @notice Token balances, keyed by holder.
    mapping(address => uint256) private _balances;
    /// @notice Aggregate outstanding supply; equals the sum of all balances.
    uint256 public totalSupply;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    // ------------------------------------------------------------------
    // Owner administration
    // ------------------------------------------------------------------

    /// @notice Grant or revoke an address's whitelist status.
    /// @dev Writes state and emits unconditionally, even when the value is
    ///      unchanged; downstream consumers dedupe events themselves.
    function setWhitelisted(address account, bool status) external onlyOwner {
        if (account == address(0)) revert ZeroAddress();
        whitelisted[account] = status;
        emit ComplianceUpdated(account, status);
    }

    /// @notice Create new tokens credited to a whitelisted recipient.
    /// @dev Reverts for non-whitelisted recipients even when the caller is the
    ///      owner; the whitelist rule is uniform.
    function mint(address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        if (!whitelisted[to]) revert NotWhitelisted();
        _balances[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    // ------------------------------------------------------------------
    // Token movement
    // ------------------------------------------------------------------

    /// @notice Transfer tokens to another whitelisted address.
    /// @dev Both sender and recipient must be whitelisted at execution time.
    ///      No zero-address guard on the sender path: unreachable through a
    ///      signed transaction.
    function transfer(address to, uint256 amount) external returns (bool) {
        if (!whitelisted[msg.sender]) revert NotWhitelisted();
        if (to == address(0)) revert ZeroAddress();
        if (!whitelisted[to]) revert NotWhitelisted();
        uint256 balance = _balances[msg.sender];
        if (balance < amount) revert InsufficientBalance();
        _balances[msg.sender] = balance - amount;
        _balances[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------

    function name() external pure returns (string memory) {
        return "Token Ledger";
    }

    function symbol() external pure returns (string memory) {
        return "TLR";
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }
}
