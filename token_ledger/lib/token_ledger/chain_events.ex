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
  Highest persisted live block for `chain_id`, or `nil` when nothing has been
  recorded yet. Orphaned rows are excluded: after a reorg rollback the resume
  cursor must refetch the canonical chain, not park on the phantom tip.
  """
  @spec max_persisted_block(integer()) :: non_neg_integer() | nil
  def max_persisted_block(chain_id) do
    Event
    |> where(chain_id: ^chain_id, orphaned: false)
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
  Live block hashes by block number over `[from_block, to_block]`, for the
  watcher's fork walk. Orphaned rows are excluded: the walk compares the
  canonical chain against what we currently believe, not superseded evidence.
  """
  @spec live_block_hashes(integer(), non_neg_integer(), non_neg_integer()) :: %{
          non_neg_integer() => String.t()
        }
  def live_block_hashes(chain_id, from_block, to_block) do
    Event
    |> where(
      [e],
      e.chain_id == ^chain_id and not e.orphaned and
        e.block_number >= ^from_block and e.block_number <= ^to_block
    )
    |> group_by([e], e.block_number)
    |> select([e], {e.block_number, max(e.block_hash)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Marks all unconfirmed live events over `[from_block, to_block]` orphaned
  in one statement; returns the count marked. Confirmed rows are excluded:
  confirmation is the finality boundary, so a confirmed event can never be
  orphaned even if a fork range is computed over it.
  """
  @spec mark_range_orphaned(integer(), non_neg_integer(), non_neg_integer()) ::
          {:ok, non_neg_integer()}
  def mark_range_orphaned(chain_id, from_block, to_block) do
    {count, _} =
      Event
      |> where(
        [e],
        e.chain_id == ^chain_id and not e.orphaned and not e.confirmed and
          e.block_number >= ^from_block and e.block_number <= ^to_block
      )
      |> Repo.update_all(set: [orphaned: true])

    {:ok, count}
  end

  @doc """
  Flips `confirmed = true` on live rows at or under `through_block`. Depth
  arithmetic lives with the caller (the watcher): through_block is
  `tip - confirmation_depth`.
  """
  @spec confirm_through(integer(), non_neg_integer()) :: {:ok, non_neg_integer()}
  def confirm_through(chain_id, through_block) do
    {count, _} =
      Event
      |> where(
        [e],
        e.chain_id == ^chain_id and not e.orphaned and not e.confirmed and
          e.block_number <= ^through_block
      )
      |> Repo.update_all(set: [confirmed: true])

    {:ok, count}
  end

  @doc """
  Counts live (non-orphaned) events over `[from_block, to_block]` — used to
  fill `events_reapplied` once a rollback's refetch has covered the range.
  """
  @spec count_live_events(integer(), non_neg_integer(), non_neg_integer()) ::
          non_neg_integer()
  def count_live_events(chain_id, from_block, to_block) do
    Event
    |> where(
      [e],
      e.chain_id == ^chain_id and not e.orphaned and
        e.block_number >= ^from_block and e.block_number <= ^to_block
    )
    |> Repo.aggregate(:count)
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
