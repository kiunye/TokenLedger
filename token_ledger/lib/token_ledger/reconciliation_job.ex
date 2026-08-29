defmodule TokenLedger.ReconciliationJob do
  @moduledoc """
  Oban worker: scheduled anti-entropy gap detector (design decisions 6, 7).

  On each run it samples the chain height and the indexed (live-watermark)
  height, records a `reconciliation_runs` row, and — when the indexer is behind
  — nudges the listener to rewind to the first missing block. Failed RPC reads
  degrade to a gap-0 run with a `completed_at` so the incident is recorded
  rather than silently looping. The core logic lives in `run/2` (height
  injectable) so it is unit-testable without a live endpoint.
  """
  use Oban.Worker, queue: :reconciliation

  require Logger

  alias TokenLedger.ChainEventListener
  alias TokenLedger.ChainEvents
  alias TokenLedger.Reconciliation
  alias TokenLedger.RPC.Client

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"chain_id" => chain_id}}) do
    run(chain_id)
    :ok
  end

  @doc "Executes one reconciliation pass for `chain_id`."
  @spec run(integer(), keyword()) :: :ok
  def run(chain_id, opts \\ []) do
    height = Keyword.get_lazy(opts, :height, fn -> Client.height() end)

    case height do
      {:ok, chain_height} ->
        indexed_height = indexed_frontier(chain_id)
        previous = Reconciliation.last_run(chain_id)
        run = Reconciliation.start_run(chain_id, chain_height, indexed_height)

        gap = max(0, chain_height - indexed_height)

        if indexed_height < chain_height do
          # Nudge the listener to re-ingest from the first missing block. The
          # cast is a no-op if the listener isn't running (unit tests) and, with
          # the corrected frontier, a no-op when the listener is healthy.
          GenServer.cast(ChainEventListener, {:rewind, indexed_height + 1})
        end

        reorg_detected =
          Reconciliation.reorg_in_window?(
            chain_id,
            if(previous, do: previous.started_at, else: run.started_at),
            run.started_at
          )

        Reconciliation.finish_run(run, gap, reorg_detected)

      {:error, reason} ->
        Logger.warning("Reconciliation skipped: chain height read failed: #{inspect(reason)}")

        run =
          Reconciliation.start_run(
            chain_id,
            0,
            ChainEvents.max_persisted_block(chain_id) || 0
          )

        Reconciliation.finish_run(run, 0, false)
    end

    :ok
  end

  # The indexer's true ingestion frontier is the listener's next-to-ingest
  # cursor minus one — not the highest block that happened to carry a watched
  # event. On a quiet contract most blocks have no events, so the persisted
  # max block would sit far below the real frontier and manufacture a bogus
  # gap. We ask the listener with a short timeout: a live, idle listener
  # answers immediately, while a listener stuck on a slow/hung RPC call (or
  # crashed) reads as unresponsive — in which case we fall back to the
  # persisted max block, which is exactly the "genuine lag" signal we want.
  defp indexed_frontier(chain_id) do
    case safe_listener_next_block() do
      next when is_integer(next) and next > 0 -> next - 1
      _ -> ChainEvents.max_persisted_block(chain_id) || 0
    end
  end

  defp safe_listener_next_block do
    GenServer.call(ChainEventListener, :next_block, 1_000)
  catch
    :exit, _ -> nil
  end
end
