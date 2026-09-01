defmodule TokenLedgerWeb.Api.BalanceController do
  @moduledoc """
  Stub balance endpoint: returns confirmed amount for an address.
  """

  use TokenLedgerWeb, :controller

  def show(conn, _params) do
    json(conn, %{balance: "0"})
  end
end
