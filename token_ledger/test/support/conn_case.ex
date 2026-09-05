defmodule TokenLedgerWeb.Api.ConnCase do
  @moduledoc """
  Shared setup for API controller tests.

  Brings in `Phoenix.ConnTest` (which provides `build_conn/0`, `get/3`,
  `post/3`, `json_response/2`, etc.) and pins `@endpoint` so request helpers
  dispatch against the real endpoint without starting an HTTP server.

  Pins `:token_ledger, :chain_id` to a non-default value for the lifetime of
  every test in this case template. Integration suites own chain 31_337
  (Anvil default) and share the same database; controller fixtures clear
  `chain_events` rows in setup to get a clean assertion surface, which would
  otherwise wipe in-flight integration rows. By routing every controller
  request through `ChainConfig` to 99_999, the controller test's fixtures
  and queries stay self-consistent on chain 99_999 and never touch chain
  31_337's rows. The integration tests' setup_all explicitly re-asserts
  31_337 just before each `ChainApp.start` so the listener always sees its
  intended chain regardless of test interleaving.
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
