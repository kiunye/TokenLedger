defmodule TokenLedgerWeb.Api.BalanceController do
  use TokenLedgerWeb, :controller

  action_fallback TokenLedgerWeb.FallbackController

  def show(conn, %{"address" => address}) do
    balance = "0" # TODO: call TokenLedger.Balances.get_balance!(address)
    json(conn, %{"address" => address, "balance" => balance})
  end
end