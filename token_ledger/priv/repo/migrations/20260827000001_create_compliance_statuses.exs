defmodule TokenLedger.Repo.Migrations.CreateComplianceStatuses do
  use Ecto.Migration

  @doc """
  Creates the `compliance_statuses` table (Phase 5): the operator-facing,
  off-chain-first compliance workflow state. One row per addressed account
  once an action is initiated; `status` moves `pending_revocation` /
  `pending_reinstate` → `enforced` when the on-chain `ComplianceUpdated` is
  confirmed, with the `intent` field disambiguating what "enforced" means
  (revoked vs re-whitelisted). This is intent+confirmation tracking — the
  projection's `accounts.whitelisted` remains the derived source of truth.
  """
  def change do
    create table(:compliance_statuses, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :address, :string, null: false
      add :status, :string, null: false
      add :intent, :string, null: false
      add :submitted_tx_hash, :string, null: true
      add :submitted_at, :utc_datetime, null: true
      add :initiated_at, :utc_datetime, null: false
      add :confirmed_at, :utc_datetime, null: true
      add :last_error, :string, null: true

      timestamps()
    end

    create unique_index(:compliance_statuses, [:address])
    create index(:compliance_statuses, [:status])
  end
end
