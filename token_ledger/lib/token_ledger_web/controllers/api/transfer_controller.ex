defmodule TokenLedgerWeb.Api.TransferController do
  @moduledoc """
  Stub transfer simulate endpoint: predicts revert vs success.
  """

  use TokenLedgerWeb, :controller

  def simulate(conn, _params) do
    json(conn, %{result: "ok"})
  end
end
