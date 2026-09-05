defmodule TokenLedger.ReorgWatcher do
  @moduledoc """
  Owns both finality transitions of the event log (design decisions 1, 3, 4).

  Each poll cycle: read the tip header, verify parent-hash linkage against
  the remembered recent hashes plus live `chain_events` hashes, and on
  mismatch walk backward to the fork point — detect → orphan + record →
  cast `{:rewind, fork_cursor}` to the listener → confirmation sweep →
  resolve-check, in that order.

  A fork whose agreement point lies deeper than the confirmation window is a
  critical incident, recorded unresolved, never auto-rolled-back (decision 6).
  The watcher never inserts into `chain_events`; the listener stays the sole
  writer.
  """

  use GenServer
  require Logger

  alias TokenLedger.ChainConfig
  alias TokenLedger.ChainEvents
  alias TokenLedger.ReorgEvents
  alias TokenLedger.Repo
  alias TokenLedger.RPC.Client

  # Margin beyond the confirmation depth for remembered hashes, so a fork
  # that lands a few blocks inside the window still has local evidence.
  @remember_margin 2

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(opts) do
    state = %{
      chain_id: Keyword.get(opts, :chain_id, ChainConfig.chain_id()),
      fetcher: Keyword.get(opts, :fetcher, Client),
      listener: Keyword.get(opts, :listener, TokenLedger.ChainEventListener),
      poll_interval_ms: Keyword.get(opts, :poll_interval_ms, ChainConfig.poll_interval_ms()),
      confirmation_depth: Keyword.get(opts, :confirmation_depth, ChainConfig.confirmation_depth()),
      remembered: %{},
      tip_number: nil,
      pending_correction: nil
    }

    Process.send_after(self(), :poll, 0)
    {:ok, Map.put(state, :auto_poll, Keyword.get(opts, :auto_poll, true))}
  end

  @impl true
  def handle_info(:poll, %{auto_poll: true} = state) do
    state = run_cycle(state)
    Process.send_after(self(), :poll, state.poll_interval_ms)
    {:noreply, state}
  end

  def handle_info(:poll, state), do: {:noreply, state}

  # Test seam: synchronously run one cycle without touching timers.
  @doc false
  def cycle_now(server \\ __MODULE__) do
    GenServer.call(server, :cycle_now)
  end

  @impl true
  def handle_call(:cycle_now, _from, state) do
    {:reply, :ok, run_cycle(state)}
  end

  defp run_cycle(state) do
    case fetch_tip(state) do
      {:ok, tip} ->
        state
        |> fill_window(tip)
        |> maybe_correct(tip)
        |> confirm_sweep(tip.number)
        |> maybe_resolve()
        |> adopt_tip(tip)

      :defer ->
        state
    end
  end

  defp fetch_tip(state) do
    with {:ok, height} <- state.fetcher.height(),
         {:ok, %{number: ^height} = tip} <- state.fetcher.get_block(height) do
      {:ok, tip}
    else
      {:ok, nil} ->
        Logger.warning("ReorgWatcher: tip header missing from node, deferring cycle")
        :defer

      {:ok, other} ->
        Logger.warning("ReorgWatcher: stale tip header #{inspect(other)}, deferring cycle")
        :defer

      {:error, reason} ->
        Logger.warning("ReorgWatcher: tip read failed, deferring cycle: #{inspect(reason)}")
        :defer
    end
  end

  # --- detection -----------------------------------------------------------

  defp maybe_correct(%{pending_correction: nil} = state, tip) do
    # Any unresolved audit row (an open incident, or a correction awaiting
    # reapply) halts automatic action: decision 6 keeps a broken window from
    # compounding. Resolution clears the row and detection resumes.
    if ReorgEvents.pending(state.chain_id) do
      state
    else
      case detect_fork(state, tip) do
        :no_fork -> state
        :over_depth -> incident(state, tip)
        {:fork, fork_block} -> correct(state, fork_block)
      end
    end
  end

  defp maybe_correct(state, _tip), do: state

  defp detect_fork(state, tip) do
    cond do
      # First cycle ever: no prior evidence, trust the tip and start remembering.
      state.tip_number == nil ->
        :no_fork

      tip.number == 0 ->
        :no_fork

      # The tip height itself was seen before and now hashes differently.
      # (The tip hash is adopted into memory only AFTER this check — see
      # adopt_tip/2 — otherwise every cycle would erase its own evidence.)
      differs?(state, tip.number, tip.hash) ->
        walk_back(state, tip.number, tip.number)

      # Or the parent linkage into remembered territory is broken.
      parent_differs?(state, tip) ->
        walk_back(state, tip.number - 1, tip.number)

      true ->
        :no_fork
    end
  end

  defp differs?(state, height, canonical_hash) do
    case known_hash(state, height) do
      nil -> false
      known -> known != canonical_hash
    end
  end

  defp parent_differs?(state, tip) do
    differs?(state, tip.number - 1, tip.parent_hash)
  end

  # Walks from the suspected height down to the window floor. Agreement at a
  # candidate height means everything above it was replaced: the fork point
  # is that height. Exhausting the window without agreement is over-depth.
  defp walk_back(state, candidate, tip_number) do
    floor = max(tip_number - state.confirmation_depth, 0)
    do_walk(state, candidate, floor)
  end

  defp do_walk(_state, candidate, floor) when candidate < floor, do: :over_depth

  defp do_walk(state, candidate, floor) do
    case state.fetcher.get_block(candidate) do
      {:ok, nil} ->
        do_walk(state, candidate - 1, floor)

      {:ok, %{hash: canonical_hash}} ->
        case known_hash(state, candidate) do
          nil -> do_walk(state, candidate - 1, floor)
          ^canonical_hash when candidate == 0 -> {:fork, 0}
          ^canonical_hash -> {:fork, candidate}
          _mismatch when candidate == 0 -> :over_depth
          _mismatch -> do_walk(state, candidate - 1, floor)
        end

      {:error, reason} ->
        Logger.warning("ReorgWatcher: fork walk halted on RPC error: #{inspect(reason)}")
        :no_fork
    end
  end

  defp known_hash(state, block_number) do
    Map.get(state.remembered, block_number) ||
      (ChainEvents.live_block_hashes(state.chain_id, block_number, block_number)
       |> Map.get(block_number))
  end

  # --- correction ----------------------------------------------------------

  defp incident(state, tip) do
    Logger.critical(
      "ReorgWatcher: fork extends past the confirmation window at tip #{tip.number}; " <>
        "recording an unresolved incident instead of auto-rolling back"
    )

    {:ok, _reorg} =
      ReorgEvents.record_detection(%{
        chain_id: state.chain_id,
        fork_block: max(tip.number - state.confirmation_depth, 0),
        depth: state.confirmation_depth,
        events_orphaned: 0
      })

    state
  end

  defp correct(state, fork_block) do
    rollback_floor = fork_block + 1
    pre_orphan_tip = state.tip_number

    {:ok, %{orphaned_count: orphaned_count, reorg: reorg}} =
      Repo.transaction(fn ->
        {:ok, orphaned_count} =
          ChainEvents.mark_range_orphaned(state.chain_id, rollback_floor, pre_orphan_tip)

        {:ok, reorg} =
          ReorgEvents.record_detection(%{
            chain_id: state.chain_id,
            fork_block: fork_block,
            depth: pre_orphan_tip - fork_block,
            events_orphaned: orphaned_count
          })

        %{orphaned_count: orphaned_count, reorg: reorg}
      end)

    Logger.warning(
      "Reorg detected: fork at #{fork_block}, depth #{pre_orphan_tip - fork_block}, " <>
        "#{orphaned_count} event(s) orphaned; rewinding listener to #{rollback_floor}"
    )

    GenServer.cast(state.listener, {:rewind, rollback_floor})

    # Drop the orphan-window from the remembered map so the next cycle's
    # `fill_window` re-fetches these heights from the chain (now canonical)
    # instead of comparing against pre-reorg hashes that would mismatch and
    # trigger a spurious second detection while the listener is still
    # re-ingesting.
    forgotten =
      state.remembered
      |> Enum.reject(fn {height, _hash} -> height >= rollback_floor and height <= pre_orphan_tip end)
      |> Map.new()

    %{state |
      pending_correction: %{reorg: reorg, fork_block: fork_block, pre_orphan_tip: pre_orphan_tip},
      remembered: forgotten}
  end

  # Resolution: the listener has re-ingested through the pre-orphan tip.
  # Progress is observed via the listener's CURSOR, not the event-row
  # watermark: a rollback range whose canonical replacements contain no
  # events leaves no rows above the fork, so the watermark would never move
  # while the cursor correctly does. Falls back to the watermark when the
  # listener is momentarily unreachable (restart window).
  defp maybe_resolve(%{pending_correction: nil} = state), do: state

  defp maybe_resolve(%{pending_correction: pending} = state) do
    if listener_progress(state) >= pending.pre_orphan_tip do
      reapplied = ChainEvents.count_live_events(state.chain_id, pending.fork_block + 1, pending.pre_orphan_tip)
      {:ok, _reorg} = ReorgEvents.mark_resolved(pending.reorg, reapplied)

      Logger.info(
        "Reorg correction resolved: fork #{pending.fork_block}, #{reapplied} event(s) reapplied"
      )

      %{state | pending_correction: nil}
    else
      state
    end
  end

  defp listener_progress(state) do
    case GenServer.call(state.listener, :next_block, 2_000) do
      next_block when is_integer(next_block) ->
        # Cursor is exclusive: next_block is the first NOT-yet-ingested block.
        max(next_block - 1, watermark(state))

      _other ->
        watermark(state)
    end
  catch
    :exit, _ -> watermark(state)
  end

  defp watermark(state), do: ChainEvents.max_persisted_block(state.chain_id) || 0

  # --- confirmation sweep --------------------------------------------------

  defp confirm_sweep(state, tip_number) do
    boundary = tip_number - state.confirmation_depth

    if boundary >= 0 do
      {:ok, confirmed} = ChainEvents.confirm_through(state.chain_id, boundary)

      if confirmed > 0 do
        Logger.info("Confirmed #{confirmed} event(s) through block #{boundary}")
      end
    end

    state
  end

  # --- remembered tip window ----------------------------------------------

  # Keeps the window CONTIGUOUS: every height in [tip - depth - margin, tip]
  # has a canonical hash. A walk over sparse tips-only memory would skip
  # evidence-free heights and false-alarm over-depth; backfilling from the
  # node costs one get_block per newly-seen height (a bounded burst on boot,
  # one call per new block steady-state).
  #
  # Split in two phases: backfill runs BEFORE detection but only fills
  # heights BELOW the tip — adopting the fresh tip hash early would erase
  # the very divergence detection is about to compare against.
  defp fill_window(state, tip) do
    floor = max(tip.number - state.confirmation_depth - @remember_margin, 0)

    filled =
      floor..(tip.number - 1)
      |> Enum.reject(&Map.has_key?(state.remembered, &1))
      |> Enum.reduce(%{}, fn height, acc ->
        case state.fetcher.get_block(height) do
          {:ok, %{hash: hash}} -> Map.put(acc, height, hash)
          _ -> acc
        end
      end)

    remembered = Map.merge(state.remembered, filled)
    %{state | remembered: remembered}
  end

  defp adopt_tip(state, tip) do
    floor = max(tip.number - state.confirmation_depth - @remember_margin, 0)

    remembered =
      state.remembered
      |> Map.put(tip.number, tip.hash)
      |> then(fn map ->
        Map.drop(map, for(height <- Map.keys(map), height < floor, do: height))
      end)

    %{state | remembered: remembered, tip_number: tip.number}
  end
end
