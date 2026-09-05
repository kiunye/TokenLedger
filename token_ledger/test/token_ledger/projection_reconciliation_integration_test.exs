defmodule TokenLedger.ProjectionReconciliationIntegrationTest do
  @moduledoc """
  Automated proof of the Phase 4 exit criteria (AGENTS.md §2):

  - 4A: a killed EventListener resumes from the last confirmed block with zero
    gap — proven by restarting it over an unconfirmed tail and asserting the
    projected balances reconstruct the canonical totals exactly, with no
    duplicate or missing live identities;
  - 4B: an induced indexer lag is detected by the reconciliation job, the gap
    is recorded in `reconciliation_runs`, and after the lag clears the live
    watermark reaches the chain height with contiguous coverage.

  Balance correctness is checked against an independent replay of the chain's
  own logs (never against the indexer's own output), so the projection is
  proven rather than round-tripped. Every wait is deadline-bounded.
  """

  use ExUnit.Case, async: false

  import TokenLedger.Test.Harness

  alias TokenLedger.Accounts.Account
  alias TokenLedger.ChainEvents
  alias TokenLedger.ChainEvents.Decoder
  alias TokenLedger.Projections.Balance
  alias TokenLedger.Projections.Checkpoint
  alias TokenLedger.Reconciliation
  alias TokenLedger.Reconciliation.Run
  alias TokenLedger.ReconciliationJob
  alias TokenLedger.ReorgEvents
  alias TokenLedger.Repo
  alias TokenLedger.RPC.Client
  alias TokenLedger.Test.{AnvilChain, ChainApp}

  import Ecto.Query
  import Decimal, only: [new: 1, equal?: 2, add: 2, sub: 2, negate: 1]

  @chain_id 31_337
  @zero "0x0000000000000000000000000000000000000000"
  @settle_timeout 120_000

  setup_all do
    {:ok, _} = AnvilChain.start()
    :ok = AnvilChain.wait_ready()

    rpc_url = AnvilChain.rpc_url()
    Application.put_env(:token_ledger, :rpc_url, rpc_url)
    Application.put_env(:token_ledger, :poll_interval_ms, 100)
    # Shallow confirmation depth so even short test chains reach finality
    # promptly; the real depth is a runtime config value, not behavior under test.
    Application.put_env(:token_ledger, :confirmation_depth, 1)

    on_exit(fn ->
      ChainApp.stop()
      AnvilChain.stop()
      Application.delete_env(:token_ledger, :contract_address)
      Application.delete_env(:token_ledger, :rpc_url)
      Application.delete_env(:token_ledger, :poll_interval_ms)
      Application.delete_env(:token_ledger, :confirmation_depth)
    end)

    %{rpc_url: rpc_url}
  end

  @tag timeout: 400_000
  test "4A: killed listener resumes from confirmed block with zero gap", %{rpc_url: rpc_url} do
    truncate_all()

    deploy = run_load_script(rpc_url, phase: 3)
    Application.put_env(:token_ledger, :contract_address, String.downcase(deploy.registry_address))
    ChainApp.start(deploy.registry_address)

    # Mint, then transfer/compliance — leave an unconfirmed tail to make the
    # restart meaningful (the listener must resume past it, not re-live it).
    run = emit(rpc_url, 1, deploy.registry_address)
    await_ingestion(rpc_url, run.expected_events)
    emit(rpc_url, 2, deploy.registry_address)

    # Kill the listener mid-stream, before the second batch is fully confirmed
    # and projected.
    old_pid = Process.whereis(TokenLedger.ChainEventListener)
    Process.exit(old_pid, :kill)

    wait_until!(30_000, fn ->
      pid = Process.whereis(TokenLedger.ChainEventListener)
      pid != nil and pid != old_pid and Process.alive?(pid)
    end, "listener restarted by its supervisor")

    # After restart it must converge to exactly the canonical totals.
    await_settled(rpc_url, deploy.registry_address)

    assert_balances_match(rpc_url, deploy.registry_address)
    assert_canonical_coverage(rpc_url, deploy.registry_address)
    assert_zero_duplicate_live_identities()

    ChainApp.stop()
  end

  @tag timeout: 400_000
  test "4B: induced lag is detected, recorded, and backfilled", %{rpc_url: rpc_url} do
    truncate_all()

    deploy = run_load_script(rpc_url, phase: 3)
    Application.put_env(:token_ledger, :contract_address, String.downcase(deploy.registry_address))
    ChainApp.start(deploy.registry_address)

    # Baseline: ingest + project a first wave.
    emit(rpc_url, 1, deploy.registry_address)
    await_settled(rpc_url, deploy.registry_address)
    baseline_tip = height!(rpc_url)

    # Blind the indexer's RPC so it stalls while the chain keeps advancing.
    Application.put_env(:token_ledger, :rpc_url, "http://127.0.0.1:1")
    Process.sleep(300)

    # Advance the chain directly (load script uses the real Anvil URL, not the
    # app's blinded one).
    emit(rpc_url, 2, deploy.registry_address)
    new_height = height!(rpc_url)
    assert new_height > baseline_tip

    # Run the reconciliation job inline against the real chain height; it must
    # observe the gap and record a run row (the listener is blind, so the row
    # is the durable proof — the actual backfill happens once RPC is restored).
    indexed_before = ChainEvents.max_persisted_block(@chain_id)
    ReconciliationJob.run(@chain_id, height: {:ok, new_height})

    run = latest_run()
    assert run != nil
    assert run.gap_blocks_backfilled > 0
    # The indexed watermark (live, non-orphaned persistence) is what the job
    # compares against the chain height — it can lag the chain tip by empty or
    # foreign-only blocks, so it is asserted against the persisted watermark,
    # not the raw chain height.
    assert run.indexed_height_at_start == indexed_before
    assert run.chain_height_at_start == new_height
    assert run.gap_blocks_backfilled == new_height - indexed_before
    assert not is_nil(run.completed_at)
    assert run.reorg_detected == false

    # Restore RPC; the listener (nudged by the job's rewind) catches up.
    Application.put_env(:token_ledger, :rpc_url, rpc_url)
    await_settled(rpc_url, deploy.registry_address)

    # The lag is fully closed: the listener cursor has reached the chain tip
    # (coverage is contiguous per-block), and balances now include the second
    # wave. `max_persisted_block` can sit below the raw tip when the top block
    # carries no watched events, so cursor position is the right signal.
    assert safe_next_block() > new_height
    assert_balances_match(rpc_url, deploy.registry_address)
    assert_canonical_coverage(rpc_url, deploy.registry_address)
    assert_zero_duplicate_live_identities()

    # The recorded run is still there, unchanged by the subsequent catch-up.
    assert latest_run().gap_blocks_backfilled > 0

    ChainApp.stop()
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp emit(rpc_url, phase, registry_address) do
    run_load_script(rpc_url, phase: phase, registry: registry_address)
  end

  defp truncate_all do
    Repo.delete_all(ChainEvents.Event)
    Repo.delete_all(ReorgEvents.ReorgEvent)
    Repo.delete_all(Run)
    Repo.delete_all(Balance)
    Repo.delete_all(Account)
    Repo.delete_all(from(c in TokenLedger.Projections.Checkpoint, where: c.chain_id == ^@chain_id))
  end

  defp await_ingestion(rpc_url, expected_count \\ 0) do
    wait_until!(@settle_timeout, fn ->
      ingested = ChainEvents.live_count(@chain_id) >= expected_count
      height = height!(rpc_url)
      next = safe_next_block()
      cursor_past_tip = is_integer(next) and next > height
      cursor_past_tip and ingested
    end, "ingestion caught up to tip with #{expected_count} live event(s)")
  end

  # Ingestion + watcher confirmation + projection all settled, and the DB
  # balances equal an independent replay of the chain's own confirmed logs.
  # Note: the watcher confirms only up to `height - confirmation_depth`, so we
  # compare against the confirmed tip rather than demanding full height.
  defp await_settled(rpc_url, registry) do
    wait_until!(@settle_timeout, fn ->
      height = height!(rpc_url)
      next = safe_next_block()
      confirmed = ChainEvents.last_confirmed_block(@chain_id)

      ingested = is_integer(next) and next > height
      confirmed != nil and ingested and balances_match?(rpc_url, registry, confirmed)
    end, "chain settled and projected")
  end

  defp expected_balances(rpc_url, registry, to_block) do
    {:ok, logs} =
      logs(rpc_url, %{
        "address" => registry,
        "fromBlock" => "0x0",
        "toBlock" => Client.integer_to_quantity(to_block)
      })

    Enum.reduce(logs, %{}, &accumulate_log/2)
  end

  defp accumulate_log(log, acc) do
    case Decoder.decode(log) do
      :ignore ->
        acc

      {:ok, "transfer", payload} ->
        apply_transfer(acc, payload)

      {:ok, "compliance_updated", _payload} ->
        acc
    end
  end

  defp apply_transfer(acc, payload) do
    from = payload["from"]
    to = payload["to"]
    amount = new(payload["amount"])

    acc
    |> debit(from, amount)
    |> credit(to, amount)
  end

  # Mints (from = zero) credit the recipient; transfers debit the sender. The
  # zero address is never an account or a debit target, mirroring the
  # projection's own rules.
  defp credit(acc, @zero, _amount), do: acc

  defp credit(acc, address, amount) do
    Map.update(acc, address, amount, &add(&1, amount))
  end

  defp debit(acc, @zero, _amount), do: acc

  defp debit(acc, address, amount) do
    Map.update(acc, address, negate(amount), &sub(&1, amount))
  end

  defp db_balances do
    Balance
    |> Repo.all()
    |> Enum.map(fn %{account_address: a, amount: amt} -> {a, amt} end)
    |> Map.new()
  end

  defp balances_match?(rpc_url, registry, to_block) do
    expected = expected_balances(rpc_url, registry, to_block)
    actual = db_balances()

    Map.keys(expected)
    |> Kernel.++(Map.keys(actual))
    |> Enum.uniq()
    |> Enum.all?(fn address ->
      exp = Map.get(expected, address, new(0))
      act = Map.get(actual, address, new(0))
      equal?(exp, act)
    end)
  end

  defp assert_balances_match(rpc_url, registry) do
    to_block = ChainEvents.last_confirmed_block(@chain_id)
    assert balances_match?(rpc_url, registry, to_block), "projected balances diverge from canonical replay"
  end

  defp latest_run do
    Run
    |> where(chain_id: ^@chain_id)
    |> order_by(desc: :started_at)
    |> limit(1)
    |> Repo.one()
  end

  defp safe_next_block do
    GenServer.call(TokenLedger.ChainEventListener, :next_block)
  catch
    :exit, _ -> nil
  end

  defp all_rows, do: ChainEvents.list_events(@chain_id)
  defp live_rows, do: Enum.filter(all_rows(), &(!&1.orphaned))

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
