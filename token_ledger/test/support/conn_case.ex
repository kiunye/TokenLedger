defmodule TokenLedgerWeb.ConnCase do
  @moduledoc """
  Test support for HTTP-level tests of `TokenLedgerWeb` controllers.

  Controller tests pin `:token_ledger, :chain_id` to a synthetic value
  (`@controller_chain_id`) so their fixture deletes and HTTP queries cannot
  collide with the integration suite's shared `:token_ledger` environment
  when both run concurrently. The previous chain_id is restored on exit so
  any setup_all that ran first (e.g. the integration suite's
  `Application.put_env(:token_ledger, :chain_id, 31_337)`) sees its value
  again.

  This case does not bring up Anvil or any supervision tree; it only sets
  per-test application env. Use `TokenLedger.Test.AnvilChain.start/1` and
  `TokenLedger.Test.ChainApp.start/1` directly when a controller test needs
  to talk to a real chain (none currently do).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Test
      import Phoenix.ConnTest
      @endpoint TokenLedgerWeb.Endpoint
    end
  end

  setup do
    previous_chain_id = Application.get_env(:token_ledger, :chain_id)
    Application.put_env(:token_ledger, :chain_id, @controller_chain_id)

    on_exit(fn ->
      case previous_chain_id do
        nil -> Application.delete_env(:token_ledger, :chain_id)
        value -> Application.put_env(:token_ledger, :chain_id, value)
      end
    end)

    :ok
  end

  @controller_chain_id 99_999
end
