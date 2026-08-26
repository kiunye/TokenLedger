defmodule TokenLedger.ReorgWatcherTest do
  # Drives the real watcher against ChainSim (no node, no timers beyond the
  # boot poll) and the shared test DB for the chain under test.
  use ExUnit.Case, async: false

  import Ecto.Query

  alias TokenLedger.ChainEvents
  alias TokenLedger.ReorgEvents
  alias TokenLedger.ReorgWatcher
  alias TokenLedger.Repo
  alias TokenLedger.Test.ChainSim
  alias TokenLedger.Test.ChainWorld

  @chain_id 92_777
  @depth 3
  @watcher Module.concat(__MODULE__, :watcher)

  # GenServer.cast into this plain test process keeps the $gen_cast envelope.
  defmacrop assert_rewind(to_block) do
    quote do
      assert_received {:"$gen_cast", {:rewind, unquote(to_block)}}
    end
  end

  defmacrop refute_rewind do
    quote do
      refute_received {:"$gen_cast", {:rewind, _}}
    end
  end

  setup do
    ChainSim.stop()

    Repo.delete_all(from(e in ChainEvents.Event, where: e.chain_id == ^@chain_id))
    Repo.delete_all(from(r in ReorgEvents.ReorgEvent, where: r.chain_id == ^@chain_id))

    {:ok, _} = ChainSim.start_link(ChainWorld.linear(6))

    # Detached start (repo convention from AnvilChain/ChainApp): ExUnit
    # reaps processes linked to the finished test process BEFORE on_exit
    # runs, which would otherwise kill the watcher mid-teardown.
    watcher_opts = [
      chain_id: @chain_id,
      fetcher: ChainSim,
      listener: self(),
      confirmation_depth: @depth,
      poll_interval_ms: 600_000,
      auto_poll: false
    ]

    {:ok, _} = GenServer.start(ReorgWatcher, watcher_opts, name: @watcher)

    # Synchronous first cycle so the initial world is definitely consumed
    # (and remembered) before any test mutates ChainSim.
    :ok = ReorgWatcher.cycle_now(@watcher)

    on_exit(fn -> if Process.whereis(@watcher), do: GenServer.stop(@watcher) end)

    :ok
  end

  describe "clean tip advance" do
    test "advancing the canonical tip records nothing and casts nothing" do
      ChainSim.set_blocks(ChainWorld.linear(7))
      :ok = ReorgWatcher.cycle_now(@watcher)

      assert ReorgEvents.list(@chain_id) == []
      refute_rewind()
    end
  end

  describe "depth-1 reorg" do
    test "orphans the replaced block's events, records depth 1, rewinds to fork+1" do
      seed_events([5])

      ChainSim.set_blocks(ChainWorld.forked(ChainWorld.linear(6), 5, 5, 5))
      :ok = ReorgWatcher.cycle_now(@watcher)

      assert_rewind(5)

      [reorg] = ReorgEvents.list(@chain_id)
      assert reorg.fork_block == 4
      assert reorg.depth == 1
      assert reorg.events_orphaned == 1
      assert reorg.resolved_at == nil

      rows = all_rows()
      assert Enum.count(rows, &(&1.orphaned && !&1.confirmed)) == 1
      assert Enum.any?(rows, &(!&1.orphaned)) == false
    end

    test "resolves once the listener watermark passes the pre-orphan tip" do
      seed_events([5])

      ChainSim.set_blocks(ChainWorld.forked(ChainWorld.linear(6), 5, 5, 5))
      :ok = ReorgWatcher.cycle_now(@watcher)
      assert_rewind(5)

      # The listener refetches the canonical block; its events land live.
      {:ok, _} =
        ChainEvents.persist_events([
          event(5, block_hash: ChainWorld.hash("b", 5), log_index: 5)
        ])

      :ok = ReorgWatcher.cycle_now(@watcher)

      [reorg] = ReorgEvents.list(@chain_id)
      assert %DateTime{} = reorg.resolved_at
      assert reorg.events_reapplied == 1
    end
  end

  describe "multi-block reorg" do
    test "walks past several mismatches and orphans the whole range" do
      seed_events([2, 3, 4, 5])

      ChainSim.set_blocks(ChainWorld.forked(ChainWorld.linear(6), 3, 5, 5))
      :ok = ReorgWatcher.cycle_now(@watcher)

      assert_rewind(3)

      [reorg] = ReorgEvents.list(@chain_id)
      assert reorg.fork_block == 2
      assert reorg.depth == 3
      assert reorg.events_orphaned == 3
    end
  end

  describe "empty-range reorg" do
    test "rewinds the cursor even when zero events were orphaned" do
      # No chain_events rows at all: detection rides purely on remembered hashes.
      ChainSim.set_blocks(ChainWorld.forked(ChainWorld.linear(6), 5, 5, 5))
      :ok = ReorgWatcher.cycle_now(@watcher)

      assert_rewind(5)

      [reorg] = ReorgEvents.list(@chain_id)
      assert reorg.events_orphaned == 0
      assert reorg.fork_block == 4
    end
  end

  describe "over-depth fork" do
    test "records an unresolved incident without orphaning or rewinding" do
      seed_events([1, 2])

      # Agreement would sit below the window floor (tip 5, depth 3).
      ChainSim.set_blocks(ChainWorld.forked(ChainWorld.linear(6), 1, 5, 5))
      :ok = ReorgWatcher.cycle_now(@watcher)

      refute_rewind()

      [incident] = ReorgEvents.list(@chain_id)
      assert incident.resolved_at == nil
      assert incident.events_orphaned == 0

      # The incident halts automatic correction: nothing marked orphaned.
      assert Enum.all?(all_rows(), &(&1.orphaned == false))

      # A follow-up cycle must not duplicate the incident row.
      :ok = ReorgWatcher.cycle_now(@watcher)
      assert Enum.count(ReorgEvents.list(@chain_id)) == 1
    end
  end

  describe "confirmation sweep" do
    test "confirms only rows at least confirmation_depth deep" do
      seed_events([0, 1, 2, 3])

      # Tip is 5 after the setup cycle; boundary = 5 - 3 = 2.
      :ok = ReorgWatcher.cycle_now(@watcher)

      confirmed =
        all_rows() |> Enum.filter(& &1.confirmed) |> Enum.map(& &1.block_number)

      assert Enum.sort(confirmed) == [0, 1, 2]

      # Tip advances to 9; boundary moves to 6 — block 3 joins the final set.
      ChainSim.set_blocks(ChainWorld.linear(10))
      :ok = ReorgWatcher.cycle_now(@watcher)
      assert Enum.count(all_rows(), & &1.confirmed) == 4
    end

    test "sweep never confirms orphaned rows" do
      # Block 4 sits above the boundary (tip 5 - depth 3 = 2), so only the
      # manual orphaning — not the sweep's own depth rule — is under test.
      seed_events([4])
      {:ok, 1} = ChainEvents.mark_range_orphaned(@chain_id, 4, 4)

      ChainSim.set_blocks(ChainWorld.linear(20))
      :ok = ReorgWatcher.cycle_now(@watcher)

      assert Enum.find(all_rows(), &(&1.block_number == 4)).confirmed == false
    end
  end

  describe "mark_range_orphaned/3 finality guard" do
    test "never marks a confirmed row orphaned even inside a rollback range" do
      seed_events([4, 5])
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 4)

      {:ok, count} = ChainEvents.mark_range_orphaned(@chain_id, 4, 5)

      assert count == 1
      rows = all_rows()
      assert Enum.find(rows, &(&1.block_number == 4)).orphaned == false
      assert Enum.find(rows, &(&1.block_number == 4)).confirmed == true
      assert Enum.find(rows, &(&1.block_number == 5)).orphaned == true
    end
  end

  defp seed_events(blocks) do
    events = Enum.map(blocks, fn b -> event(b, block_hash: ChainWorld.hash("a", b), log_index: b) end)
    {:ok, _} = ChainEvents.persist_events(events)
    :ok
  end

  defp event(block_number, opts) do
    %{
      chain_id: @chain_id,
      block_number: block_number,
      block_hash: Keyword.fetch!(opts, :block_hash),
      log_index: Keyword.get(opts, :log_index, block_number),
      event_type: "transfer",
      payload: %{"amount" => "1", "raw" => %{"topics" => [], "data" => "0x"}}
    }
  end

  defp all_rows do
    ChainEvents.Event
    |> where([e], e.chain_id == ^@chain_id)
    |> Repo.all()
  end
end
