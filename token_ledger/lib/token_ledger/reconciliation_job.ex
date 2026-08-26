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
        indexed_height = ChainEvents.max_persisted_block(chain_id) || 0
        run = Reconciliation.start_run(chain_id, chain_height, indexed_height)

        gap = max(0, chain_height - indexed_height)

        if indexed_height < chain_height do
          # Nudge the listener to re-ingest from the first missing block. The
          # cast is a no-op if the listener isn't running (unit tests).
          GenServer.cast(ChainEventListener, {:rewind, indexed_height + 1})
        end

        reorg_detected =
          Reconciliation.reorg_in_window?(
            chain_id,
            run.started_at,
            DateTime.utc_now() |> DateTime.truncate(:second)
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
end
