defmodule TokenLedger.ChainEventListener do
  @moduledoc """
  Poll-based range ingestion of chain events (design decision 2).

  Each cycle: read height → fetch logs for `[next_block .. height]` in
  bounded chunks filtered to the watched contract and the two known topic0s
  → decode → persist exactly once → advance the cursor past the fetched
  range (even where a block contained no watched events). On boot the cursor
  resumes from `max(block_number)` already persisted for the chain, falling
  back to the configured start block when the log is empty — combined with
  conflict-nothing inserts this makes restarts gap-free AND duplicate-free.

  The cursor lives in process state after init; a crash rewinds it to the DB
  watermark, which is safe precisely because replay is idempotent.
  """

  use GenServer
  require Logger

  alias TokenLedger.ChainConfig
  alias TokenLedger.ChainEvents
  alias TokenLedger.ChainEvents.Decoder
  alias TokenLedger.RPC.Client

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc "Current ingestion cursor: next block to fetch."
  @spec next_block(GenServer.server()) :: non_neg_integer()
  def next_block(server \\ __MODULE__) do
    GenServer.call(server, :next_block)
  end

  @impl true
  def init(_opts) do
    chain_id = ChainConfig.chain_id()
    contract = ChainConfig.contract_address!()

    cursor =
      case ChainEvents.max_persisted_block(chain_id) do
        nil ->
          Logger.info("Event log empty; starting fresh at block #{ChainConfig.start_block()}")
          ChainConfig.start_block()

        max_block ->
          Logger.info("Resuming ingestion after last persisted block #{max_block}")
          max_block + 1
      end

    schedule_poll(0)
    {:ok, %{chain_id: chain_id, contract_address: contract, next_block: cursor}}
  end

  @impl true
  def handle_call(:next_block, _from, state) do
    {:reply, state.next_block, state}
  end

  @impl true
  def handle_info(:poll, state) do
    state = run_cycle(state)
    schedule_poll()
    {:noreply, state}
  end

  # One polling cycle. Any RPC error ends the cycle without advancing the
  # cursor — the next tick retries the same range.
  defp run_cycle(%{next_block: next_block} = state) do
    case Client.height() do
      {:ok, height} when height >= next_block ->
        ingest_range(state, height)

      {:ok, _height} ->
        state

      {:error, reason} ->
        Logger.warning("Height read failed, retrying next cycle: #{inspect(reason)}")
        state
    end
  end

  defp ingest_range(%{next_block: next_block} = state, height) do
    chunk_end = min(next_block + ChainConfig.max_chunk_blocks() - 1, height)

    case Client.get_logs(state.contract_address, next_block, chunk_end) do
      {:ok, logs} ->
        persist_logs(state, chunk_end, logs)

      {:error, reason} ->
        Logger.warning(
          "get_logs [#{next_block}..#{chunk_end}] failed, retrying next cycle: #{inspect(reason)}"
        )

        state
    end
  end

  defp persist_logs(state, chunk_end, logs) do
    rows =
      logs
      |> Enum.map(&decode_log/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn {event_type, payload, identity} ->
        Map.merge(identity, %{chain_id: state.chain_id, event_type: event_type, payload: payload})
      end)

    case ChainEvents.persist_events(rows) do
      {:ok, inserted} when inserted > 0 ->
        Logger.info("Persisted #{inserted} event(s) up to block #{chunk_end}")

      _ ->
        :ok
    end

    advance_to(state, chunk_end)
  end

  # Decodes one raw log into {event_type, payload, identity}, nil when the
  # topic is unknown (foreign contracts are excluded by the address filter;
  # this is defense in depth).
  defp decode_log(log) do
    case Decoder.decode(log) do
      :ignore ->
        nil

      {:ok, event_type, payload} ->
        {event_type, payload,
         %{
           block_number: Client.quantity_to_integer!(log["blockNumber"]),
           block_hash: log["blockHash"],
           log_index: Client.quantity_to_integer!(log["logIndex"])
         }}
    end
  end

  defp advance_to(state, chunk_end) do
    %{state | next_block: chunk_end + 1}
  end

  defp schedule_poll(delay_ms \\ ChainConfig.poll_interval_ms()) do
    Process.send_after(self(), :poll, delay_ms)
  end
end
