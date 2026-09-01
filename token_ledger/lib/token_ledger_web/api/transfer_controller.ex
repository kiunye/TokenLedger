defmodule TokenLedgerWeb.Api.TransferController do
  use TokenLedgerWeb, :controller

  action_fallback TokenLedgerWeb.FallbackController

  def simulate(conn, %{"from" => from, "to" => to, "amount" => amount}) do
    # TODO: call TokenLedger.Transfers.simulate_transfer(from, to, amount)
    result = %{
      success?: true,
      gas_used: 0,
      return_value: <<>>,
      error: nil
    }
    json(conn, result)
  end
end