defmodule TokenLedgerWeb.Api.ConnCase do
  @moduledoc """
  Shared setup for API controller tests.

  Brings in `Phoenix.ConnTest` (which provides `build_conn/0`, `get/3`,
  `post/3`, `json_response/2`, etc.) and pins `@endpoint` so request helpers
  dispatch against the real endpoint without starting an HTTP server.

  Pins `:token_ledger, :chain_id` to a non-default value for the lifetime of
  every test in this case template. Integration suites own chain 31_337
  (Anvil default) and share the same database; without this override,
  controller test `delete_all` calls would wipe in-flight integration rows,
  and `Application.put_env(:chain_id, 31_337)` in an integration `setup_all`
  could be observed by a concurrent controller test (reversing the fix on
  the way out). The integration tests reassert 31_337 in their own
  `setup_all`, so any controller that runs first gets overwritten by the
  integration setup before the listener ever calls `ChainConfig.chain_id/0`,
  and any integration `setup_all` that runs first restores 31_337 before
  the controller's test process touches the env again.
  """
  use ExUnit.CaseTemplate

  @controller_chain_id 99_999

  using do
    quote do
      use Phoenix.ConnTest
      import Plug.Conn

      @endpoint TokenLedgerWeb.Endpoint

      setup do
        previous = Application.get_env(:token_ledger, :chain_id)
        Application.put_env(:token_ledger, :chain_id, unquote(@controller_chain_id))

        on_exit(fn ->
          if is_nil(previous) do
            Application.delete_env(:token_ledger, :chain_id)
          else
            Application.put_env(:token_ledger, :chain_id, previous)
          end
        end)

        :ok
      end
    end
  end
end
