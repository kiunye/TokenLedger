defmodule TokenLedger.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  @doc """
  Creates the `accounts` projection table (design decision 1): the whitelist
  mirror derived from `ComplianceUpdated` events. The address is stored
  lowercased and uniquely indexed, matching decoder output. `role` defaults to
  investor and `whitelisted` to false; both are materialized from the event log
  by `TokenLedger.Projection`.
  """
  def change do
    create table(:accounts, primary_key: false) do
      add :address, :string, primary_key: true
      add :whitelisted, :boolean, null: false, default: false
      add :role, :string, null: false, default: "investor"

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts, [:address])
  end
end
