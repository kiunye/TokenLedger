defmodule TokenLedger.ProjectionWorker do
  @moduledoc """
  Drives the projection to convergence (design decision 3 / §4.3).

  A poll loop applies confirmed events in bounded batches until the projection
  watermark reaches the confirmed tip, then idles until the next tick. Each pass
  drains (re-applying batches until none remain) so a burst of confirmations is
  consumed promptly rather than one batch per interval. State is the DB
  checkpoint, so a crash restarts from the last applied batch with no gap.

  Started as the fourth `:permanent` child of `TokenLedger.Sepolia.Supervisor`
  under `:rest_for_one`; placement and restart semantics are fixed by the doc.
  """
  use GenServer
  require Logger

  alias TokenLedger.ChainConfig
  alias TokenLedger.Projection

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    state = %{
      chain_id: Keyword.get(opts, :chain_id, ChainConfig.chain_id()),
      batch_size: Keyword.get(opts, :batch_size, 500),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, ChainConfig.poll_interval_ms())
    }

    schedule_poll(0)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = drain(state)
    schedule_poll(state.poll_interval_ms)
    {:noreply, state}
  end

  # Apply batches back-to-back until the projection is caught up, then return.
  defp drain(state) do
    case Projection.apply_batch(state.chain_id, state.batch_size) do
      {:ok, count, _cursor} when count > 0 ->
        Logger.debug("ProjectionWorker applied #{count} event(s)")
        drain(state)

      {:ok, 0, _cursor} ->
        state

      {:error, reason} ->
        Logger.warning("ProjectionWorker pass failed: #{inspect(reason)}")
        state
    end
  end

  defp schedule_poll(delay_ms) do
    Process.send_after(self(), :poll, delay_ms)
  end
end
