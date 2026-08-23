defmodule TokenLedger.Repo.Migrations.CreateChainEvents do
  use Ecto.Migration

  @doc """
  Creates the `chain_events` write-ahead log per architecture §3.2.

  The unique index on (chain_id, block_number, log_index) is the dedupe
  authority: replaying any block range conflicts into a no-op instead of
  duplicating rows.
  """
  def change do
    create table(:chain_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :chain_id, :integer, null: false
      add :block_number, :bigint, null: false
      add :block_hash, :string, null: false
      add :log_index, :integer, null: false
      add :event_type, :string, null: false
      add :payload, :map, null: false
      add :confirmed, :boolean, default: false, null: false
      add :orphaned, :boolean, default: false, null: false

      timestamps(updated_at: false, type: :utc_datetime)
    end

    create unique_index(:chain_events, [:chain_id, :block_number, :log_index])
  end
end
