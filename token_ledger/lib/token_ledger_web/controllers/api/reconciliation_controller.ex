defmodule TokenLedgerWeb.Api.ReconciliationController do
  @moduledoc """
  Stub reconciliation status endpoint.
  """

  use TokenLedgerWeb, :controller

  def status(conn, _params) do
    json(conn, %{status: "ok"})
  end
end
