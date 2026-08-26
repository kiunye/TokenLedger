defmodule TokenLedger.Repo.Migrations.ChainEventsPartialUniqueIndex do
  use Ecto.Migration

  @doc """
  Narrows the dedupe authority to live rows only.

  The original full unique index on (chain_id, block_number, log_index) made
  replay idempotent, but it would also swallow canonical replacement events
  once a reorg marks the originals orphaned — same identity, conflict-nothing,
  silent drop. The partial index keeps exactly-once semantics for live rows
  while letting canonical events insert beside their orphaned predecessors.
  """
  def change do
    drop unique_index(:chain_events, [:chain_id, :block_number, :log_index])

    create unique_index(:chain_events, [:chain_id, :block_number, :log_index],
             where: "orphaned = false",
             name: :chain_events_live_uniqueness_index
           )
  end
end
