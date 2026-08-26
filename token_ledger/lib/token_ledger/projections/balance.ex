defmodule TokenLedger.Projections.Balance do
  @moduledoc """
  Projected token balance for one account (design decision 1/8). `amount` is an
  unconstrained numeric so uint256 values need no scaling; `as_of_block` is the
  block of the last applied event that touched this account.
  """
  use Ecto.Schema

  @primary_key false
  schema "balances" do
    field(:account_address, :string, primary_key: true)
    field(:amount, :decimal, default: 0)
    field(:as_of_block, :integer)

    timestamps(type: :utc_datetime)
  end
end
