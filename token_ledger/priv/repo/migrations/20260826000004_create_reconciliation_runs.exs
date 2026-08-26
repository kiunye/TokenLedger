defmodule TokenLedger.Repo.Migrations.CreateReconciliationRuns do
  use Ecto.Migration

  @doc """
  Creates the `reconciliation_runs` audit table (design decision 7): one row per
  scheduled reconciliation pass recording the heights at start, the gap
  backfilled, and whether a reorg was observed inside the run window. The table
  makes "an induced gap is detected and backfilled" a queryable fact.
  """
  def change do
    create table(:reconciliation_runs, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :chain_id, :integer, null: false
      add :started_at, :utc_datetime, null: false
      add :completed_at, :utc_datetime, null: true
      add :chain_height_at_start, :bigint, null: false
      add :indexed_height_at_start, :bigint, null: false
      add :gap_blocks_backfilled, :integer, null: false, default: 0
      add :reorg_detected, :boolean, null: false, default: false

      timestamps(updated_at: false, type: :utc_datetime)
    end

    create index(:reconciliation_runs, [:chain_id, :started_at])
  end
end
