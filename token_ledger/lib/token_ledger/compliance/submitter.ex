defmodule TokenLedger.Compliance.Submitter do
  @moduledoc """
  Dispatch + behaviour for submitting compliance transactions (Phase 5).

  `submit_revocation/1` and `submit_reinstate/1` route to the configured
  implementation module (config `:compliance_submitter`, default
  `TokenLedger.Compliance.NodeSubmitter`). The implementation delegates to the
  signing authority — node-side via `eth_sendTransaction` for the default
  Anvil/transaction-node setup, or a production external signer in Phase 7.
  The key is held by that authority, never in application memory.

  This indirection lets tests inject a stub and lets Phase 7 swap the signer
  without touching the compliance workflow logic.
  """

  @callback submit_revocation(String.t()) :: {:ok, String.t()} | {:error, term()}
  @callback submit_reinstate(String.t()) :: {:ok, String.t()} | {:error, term()}

  @doc "Submits the on-chain `setWhitelisted(addr, false)` revocation."
  @spec submit_revocation(String.t()) :: {:ok, String.t()} | {:error, term()}
  def submit_revocation(address), do: impl().submit_revocation(address)

  @doc "Submits the on-chain `setWhitelisted(addr, true)` re-whitelist."
  @spec submit_reinstate(String.t()) :: {:ok, String.t()} | {:error, term()}
  def submit_reinstate(address), do: impl().submit_reinstate(address)

  @doc "Resolves which submitter module handles submission (configurable for tests/Phase 7)."
  def impl do
    Application.get_env(:token_ledger, :compliance_submitter, TokenLedger.Compliance.NodeSubmitter)
  end
end
