defmodule TokenLedger.ChainEvents do
  @moduledoc """
  Persistence boundary for the event log.

  Ingestion records what happened; projection (later phases) derives what it
  means (CONTEXT.md). Every write goes through `persist_events/2`, whose
  conflict-nothing insert against the unique `(chain_id, block_number,
  log_index)` index makes replay a no-op — the database, not application
  memory, is the dedupe authority (design decision 3).
  """

  import Ecto.Query

  alias TokenLedger.ChainEvents.Event
  alias TokenLedger.Repo

  @doc """
  Inserts event rows idempotently and returns `{:ok, inserted_count}` where
  the count is only the rows that were actually new. Re-inserting an
  already-persisted range therefore returns `{:ok, 0}` and leaves existing
  rows untouched.

  `events` is a list of maps with keys `:chain_id, :block_number,
  :block_hash, :log_index, :event_type, :payload` (see
  `TokenLedger.ChainEvents.Event.row/2`). Duplicate keys *within* one call
  are deduped before insert so a single overlapping batch cannot trip on
  itself.
  """
  @spec persist_events([map()], keyword()) :: {:ok, non_neg_integer()}
  def persist_events(events, _opts \\ []) when is_list(events) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      events
      |> Enum.map(&Event.row(&1, now))
      |> Enum.uniq_by(&{&1.chain_id, &1.block_number, &1.log_index})

    {count, _} =
      Repo.insert_all(Event, rows, on_conflict: :nothing)

    {:ok, count}
  end

  @doc """
  Highest persisted block for `chain_id`, or `nil` when nothing has been
  recorded yet. This is the restart-resume cursor source.
  """
  @spec max_persisted_block(integer()) :: non_neg_integer() | nil
  def max_persisted_block(chain_id) do
    Event
    |> where(chain_id: ^chain_id)
    |> select([e], max(e.block_number))
    |> Repo.one()
  end

  @doc """
  All events for `chain_id`, ordered by block then log index. Test and
  verification helper; production reads go through projections later.
  """
  @spec list_events(integer()) :: [Event.t()]
  def list_events(chain_id) do
    Event
    |> where(chain_id: ^chain_id)
    |> order_by([e], asc: e.block_number, asc: e.log_index)
    |> Repo.all()
  end

  @doc """
  Number of distinct (block_number) values with at least one persisted event.
  """
  @spec count_distinct_blocks(integer()) :: non_neg_integer()
  def count_distinct_blocks(chain_id) do
    Event
    |> where(chain_id: ^chain_id)
    |> select([e], count(e.block_number, :distinct))
    |> Repo.one()
    |> Kernel.||(0)
  end
end
