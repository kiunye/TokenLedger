defmodule TokenLedgerWeb.Api.ConnCase do
  @moduledoc """
  Shared setup for API controller tests.

  Brings in `Phoenix.ConnTest` (which provides `build_conn/0`, `get/3`,
  `post/3`, `json_response/2`, etc.) and pins `@endpoint` so request helpers
  dispatch against the real endpoint without starting an HTTP server.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Phoenix.ConnTest
      import Plug.Conn

      @endpoint TokenLedgerWeb.Endpoint
    end
  end
end