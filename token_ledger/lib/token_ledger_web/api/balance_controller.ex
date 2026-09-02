defmodule TokenLedgerWeb.Api.BalanceController do
  @moduledoc """
  Returns the confirmed, projected token balance for an address.

  The balance is read from the `balances` projection table, which is
  maintained by the ProjectionWorker from confirmed-only events. This
  ensures the API never exposes unconfirmed or orphaned state.
  """

  use TokenLedgerWeb, :controller

  alias TokenLedger.Projections.Balance
  alias TokenLedger.Repo

  def show(conn, %{"address" => address}) do
    balance =
      case Repo.get(Balance, address) do
        nil -> %Balance{account_address: address, amount: Decimal.new(0), as_of_block: 0}
        balance -> balance
      end

    json(conn, %{
      "address" => balance.account_address,
      "balance" => balance.amount |> Decimal.to_string(),
      "as_of_block" => balance.as_of_block
    })
  end
end