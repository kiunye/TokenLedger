defmodule TokenLedger.Accounts.Account do
  @moduledoc """
  The whitelist mirror projected from `ComplianceUpdated` events (design
  decision 1). `address` is the lowercased primary key as emitted by the
  decoder; `whitelisted` and `role` are materialized by `TokenLedger.Projection`.
  """
  use Ecto.Schema

  @primary_key false
  schema "accounts" do
    field(:address, :string, primary_key: true)
    field(:whitelisted, :boolean, default: false)
    field(:role, :string, default: "investor")

    timestamps(type: :utc_datetime)
  end
end
