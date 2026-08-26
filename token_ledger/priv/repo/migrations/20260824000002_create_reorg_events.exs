defmodule TokenLedger.Repo.Migrations.CreateReorgEvents do
  use Ecto.Migration

  @doc """
  Creates the `reorg_events` audit table (design decision 5): one row per
  detected reorg correction, so "the system detects and recovers from reorgs"
  is a queryable fact rather than a log-grep.
  """
  def change do
    create table(:reorg_events, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :chain_id, :integer, null: false
      add :fork_block, :bigint, null: false
      add :depth, :integer, null: false
      add :events_orphaned, :integer, null: false, default: 0
      add :events_reapplied, :integer, null: false, default: 0
      add :detected_at, :utc_datetime, null: false
      add :resolved_at, :utc_datetime, null: true

      timestamps(updated_at: false, type: :utc_datetime)
    end

    create index(:reorg_events, [:chain_id, :fork_block])
  end
end
