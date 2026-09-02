defmodule TokenLedger.Repo.Migrations.AddConfirmedEventsIndex do
  use Ecto.Migration

  @moduledoc """
  Adds a composite index to optimize the common pattern of reading confirmed,
  non-orphaned events in block-number/log-index order for a given chain.

  The existing unique index on (chain_id, block_number, log_index) does not
  cover the `confirmed`/`orphaned` filter that the dashboard and projection
  rely on. This partial index supports efficient confirmed-only reads.
  """

  def change do
    create index(
             :chain_events,
             [:chain_id, :block_number, :log_index],
             where: "confirmed = true AND orphaned = false",
             name: :confirmed_events_tip
           )
  end
end
