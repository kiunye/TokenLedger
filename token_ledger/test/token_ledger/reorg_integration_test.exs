defmodule TokenLedger.ReorgIntegrationTest do
  @moduledoc """
  Automated proof of the reorg-handling exit criterion (AGENTS.md §2):

  - a real `anvil_reorg` replaces blocks whose events the indexer already
    persisted → the watcher orphans them, records the correction, rewinds
    the listener, and the canonical range is re-ingested exactly once;
  - a reorg of an event-free block range still corrects the cursor;
  - a listener restart after a rollback resumes cleanly without reviving
    orphaned rows.

  Every wait is deadline-bounded polling; nothing is sleep-tuned.
  """

  use ExUnit.Case, async: false

  import TokenLedger.Test.Harness

  alias TokenLedger.ChainEvents
  alias TokenLedger.ReorgEvents
  alias TokenLedger.Repo
  alias TokenLedger.RPC.Client
  alias TokenLedger.Test.{AnvilChain, ChainApp}

  @chain_id 31_337
  # Production confirmation depth (§2.5); deep rows get mined past it below.
  @catchup_timeout 120_000

  setup_all do
    {:ok, _} = AnvilChain.start()
    :ok = AnvilChain.wait_ready()

    rpc_url = AnvilChain.rpc_url()
    Application.put_env(:token_ledger, :rpc_url, rpc_url)
    Application.put_env(:token_ledger, :poll_interval_ms, 100)

    on_exit(fn ->
      ChainApp.stop()
      AnvilChain.stop()
      Application.delete_env(:token_ledger, :contract_address)
      Application.delete_env(:token_ledger, :rpc_url)
      Application.delete_env(:token_ledger, :poll_interval_ms)
      Application.delete_env(:token_ledger, :chain_id)
    end)

    %{rpc_url: rpc_url}
  end

  @tag timeout: 300_000
  test "anvil reorg smoke: forced fork changes canonical hashes", %{rpc_url: rpc_url} do
    deploy = deploy_and_start(rpc_url)

    emit(rpc_url, 1, deploy.registry_address)
    await_ingestion(rpc_url)

    h = height!(rpc_url)
    before = block_hash!(rpc_url, h)

    reorg!(rpc_url, 1)

    after_hash = poll_hash_change(rpc_url, h, before)

    assert after_hash != before, "anvil_reorg produced no hash divergence at #{h}"
    ChainApp.stop()
  end

  @tag timeout: 300_000
  test "reorg over ingested events: rollback, reapply, audit row", %{rpc_url: rpc_url} do
    truncate_all()

    deploy = run_load_script(rpc_url, phase: 3)
    Application.put_env(:token_ledger, :contract_address, String.downcase(deploy.registry_address))
    ChainApp.start(deploy.registry_address)

    run = emit(rpc_url, 1, deploy.registry_address)
    await_ingestion(rpc_url)

    pre_tip = height!(rpc_url)
    pre_live = live_rows()
    assert length(pre_live) == run.expected_events

    # Replace the top of the chain — the freshly emitted events sit inside
    # the replaced window.
    reorg!(rpc_url, 3)

    # Deadline-bounded resolution: the watcher must detect, orphan, rewind,
    # and the listener must re-ingest through the old tip.
    wait_until!(@catchup_timeout, fn ->
      case resolved_correction() do
        nil -> false
        reorg -> reorg.events_orphaned > 0 and reorg.resolved_at != nil
      end
    end, "reorg correction resolved with orphans")

    reorg_row = resolved_correction()
    assert reorg_row.fork_block >= pre_tip - 4
    assert reorg_row.depth <= 5

    # Orphaned evidence retained with its superseded hashes...
    orphans = orphaned_rows()
    assert orphans != []
    assert Enum.all?(orphans, &(&1.orphaned == true))

    # ...and live state matches the canonical chain exactly (per-block).
    assert_canonical_coverage(rpc_url, deploy.registry_address)

    # No confirmed row was ever orphaned.
    assert Enum.all?(all_rows(), fn r -> not (r.confirmed and r.orphaned) end)

    ChainApp.stop()
  end

  @tag timeout: 300_000
  test "empty-range reorg corrects cursor with zero orphans", %{rpc_url: rpc_url} do
    truncate_all()

    deploy = run_load_script(rpc_url, phase: 3)
    Application.put_env(:token_ledger, :contract_address, String.downcase(deploy.registry_address))
    ChainApp.start(deploy.registry_address)

    emit(rpc_url, 1, deploy.registry_address)
    await_ingestion(rpc_url)

    # Mine quiet blocks so the replaced window contains no watched events.
    mine_empty(4)
    await_cursor_past(height!(rpc_url))

    # The watcher polls slower than the listener advances; give it a cycle
    # to memorize the pre-reorg tip, otherwise the fork erases its own
    # evidence before any cycle compares against it.
    tip_before_reorg = height!(rpc_url)

    wait_until!(10_000, fn ->
      case Process.whereis(TokenLedger.ReorgWatcher) do
        nil -> false
        pid -> tip_before_reorg in Map.keys(:sys.get_state(pid).remembered)
      end
    end, "watcher remembered pre-reorg tip", 20)

    live_before = Enum.count(live_rows())

    reorg!(rpc_url, 2)

    wait_until!(@catchup_timeout, fn ->
      case resolved_correction() do
        nil -> false
        reorg -> reorg.events_orphaned == 0 and reorg.resolved_at != nil
      end
    end, "empty-range correction resolved")

    # Zero orphans, no live loss, cursor back under control.
    assert orphaned_rows() == []
    assert Enum.count(live_rows()) == live_before

    post_tip = height!(rpc_url)
    next = safe_next_block()
    assert is_integer(next) and next > post_tip

    ChainApp.stop()
  end

  @tag timeout: 300_000
  test "listener restart after a completed rollback resumes without reviving orphans", %{
    rpc_url: rpc_url
  } do
    truncate_all()

    deploy = run_load_script(rpc_url, phase: 3)
    Application.put_env(:token_ledger, :contract_address, String.downcase(deploy.registry_address))
    ChainApp.start(deploy.registry_address)

    emit(rpc_url, 1, deploy.registry_address)
    await_ingestion(rpc_url)

    # Deep enough to reach event blocks even when foreign-contract txs fill
    # the very top of the chain.
    reorg!(rpc_url, 8)

    wait_until!(@catchup_timeout, fn ->
      case resolved_correction_with_orphans() do
        nil -> false
        _reorg -> true
      end
    end, "rollback with orphans resolved before restart")

    orphans_before = Enum.count(orphaned_rows())
    assert orphans_before > 0

    # Kill mid-life after the rollback; restart must resume from the live
    # watermark (orphan-excluded), never re-living orphaned rows.
    live_before_restart = live_rows()
    old_pid = Process.whereis(TokenLedger.ChainEventListener)
    Process.exit(old_pid, :kill)

    wait_until!(30_000, fn ->
      pid = Process.whereis(TokenLedger.ChainEventListener)
      pid != nil and pid != old_pid and Process.alive?(pid)
    end, "listener restarted by its supervisor")

    # A buggy resume (cursor derived from ALL persisted rows) would park
    # above the orphaned range and leave the log permanently inconsistent;
    # the observable contract is: orphans stay orphaned, nothing revives,
    # nothing duplicates. Cursor arithmetic itself is pinned by unit tests.
    wait_until!(@catchup_timeout, fn ->
      next = safe_next_block()
      is_integer(next) and next > height!(rpc_url)
    end, "post-restart cursor passed canonical tip")

    # Orphan count unchanged across the restart boundary.
    assert Enum.count(orphaned_rows()) == orphans_before
    assert_zero_duplicate_live_identities()
    assert length(live_rows()) == length(live_before_restart)

    ChainApp.stop()
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp deploy_and_start(rpc_url) do
    truncate_all()
    deploy = run_load_script(rpc_url, phase: 3)
    Application.put_env(:token_ledger, :contract_address, String.downcase(deploy.registry_address))
    ChainApp.start(deploy.registry_address)
    deploy
  end

  defp emit(rpc_url, phase, registry_address) do
    run_load_script(rpc_url, phase: phase, registry: registry_address)
  end

  defp truncate_all do
    Repo.delete_all(ChainEvents.Event)
    Repo.delete_all(ReorgEvents.ReorgEvent)
  end

  defp all_rows, do: ChainEvents.list_events(@chain_id)
  defp live_rows, do: Enum.filter(all_rows(), &(!&1.orphaned))
  defp orphaned_rows, do: Enum.filter(all_rows(), &(&1.orphaned))

  defp resolved_correction do
    Enum.find(ReorgEvents.list(@chain_id), fn
      %{resolved_at: %DateTime{}} -> true
      _ -> false
    end)
  end

  defp resolved_correction_with_orphans do
    Enum.find(ReorgEvents.list(@chain_id), fn
      %{resolved_at: %DateTime{}, events_orphaned: n} when n > 0 -> true
      _ -> false
    end)
  end

  defp await_ingestion(rpc_url) do
    wait_until!(@catchup_timeout, fn ->
      height = height!(rpc_url)
      next = safe_next_block()
      is_integer(next) and next > height
    end, "ingestion caught up to tip")
  end

  defp await_cursor_past(target) do
    wait_until!(@catchup_timeout, fn ->
      next = safe_next_block()
      is_integer(next) and next > target
    end, "cursor passed #{target}")
  end

  defp safe_next_block do
    GenServer.call(TokenLedger.ChainEventListener, :next_block)
  catch
    :exit, _ -> nil
  end

  defp poll_hash_change(rpc_url, number, before) do
    wait_until!(@catchup_timeout, fn ->
      block_hash!(rpc_url, number) != before
    end, "canonical hash at #{number} changed")

    block_hash!(rpc_url, number)
  end

  defp mine_empty(count) when count >= 1 do
    for _ <- 1..count do
      {:ok, _} = Ethereumex.HttpClient.request("evm_mine", [], url: AnvilChain.rpc_url())
    end

    :ok
  end

  defp assert_canonical_coverage(rpc_url, registry_address) do
    height = height!(rpc_url)
    {:ok, logs} = logs(rpc_url, %{
      "address" => registry_address,
      "fromBlock" => "0x0",
      "toBlock" => Client.integer_to_quantity(height)
    })

    chain_blocks = per_block_counts(logs)
    db_blocks = per_block_counts(live_rows())

    assert db_blocks == chain_blocks
  end

  defp per_block_counts(enum) do
    enum
    |> Enum.group_by(fn
      %{"blockNumber" => quantity} -> Client.quantity_to_integer!(quantity)
      %{block_number: block} -> block
    end)
    |> Map.new(fn {block, items} -> {block, length(items)} end)
  end

  defp assert_zero_duplicate_live_identities do
    pairs = Enum.map(live_rows(), &{&1.block_number, &1.log_index})
    assert pairs == Enum.uniq(pairs), "duplicate live identities after restart"
  end
end
