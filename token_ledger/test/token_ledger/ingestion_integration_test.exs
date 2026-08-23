defmodule TokenLedger.IngestionIntegrationTest do
  @moduledoc """
  Automated proof of the event-indexer exit criterion (AGENTS.md §2):

  - scripted Foundry load (~500 mixed events) against a live Anvil while the
    real supervision tree runs → persisted == emitted, zero duplicates,
    contiguous block coverage, foreign-contract logs ignored;
  - listener killed mid-run → supervisor restarts it, resume crosses the
    boundary with no gap and no duplicate;
  - transient RPC outage → bounded retries ride it out, ingestion completes
    exactly once after recovery.

  Every wait is deadline-bounded polling (`wait_until`); nothing is tuned to
  sleeps. Tests share one Anvil node but each deploys a FRESH registry, so
  earlier tests' events are excluded by the very address filter under test.
  """

  use ExUnit.Case, async: false

  import TokenLedger.Test.Harness

  alias TokenLedger.ChainEvents
  alias TokenLedger.Repo
  alias TokenLedger.RPC.Client
  alias TokenLedger.Test.{AnvilChain, ChainApp}

  @chain_id 31_337
  @zero_address "0x0000000000000000000000000000000000000000"
  # Generous-but-bounded: local catch-up lands in seconds. The deadline makes
  # a broken pipeline fail loudly with diagnostics instead of hanging.
  @catchup_timeout 120_000

  setup_all do
    {:ok, _} = AnvilChain.start()
    :ok = AnvilChain.wait_ready()

    rpc_url = AnvilChain.rpc_url()
    Application.put_env(:token_ledger, :rpc_url, rpc_url)
    Application.put_env(:token_ledger, :poll_interval_ms, 150)

    on_exit(fn ->
      ChainApp.stop()
      AnvilChain.stop()
      Application.delete_env(:token_ledger, :contract_address)
      Application.delete_env(:token_ledger, :rpc_url)
      Application.delete_env(:token_ledger, :poll_interval_ms)
    end)

    %{rpc_url: rpc_url}
  end

  @tag timeout: 300_000
  test "load run captures every emitted event exactly once", %{rpc_url: rpc_url} do
    deploy = deploy_and_start(rpc_url)

    run = emit(rpc_url, 0, deploy.registry_address)
    await_catchup(rpc_url, run.expected_events)

    rows = all_rows()

    # Scenario: Load run captures everything.
    assert length(rows) == run.expected_events

    assert_zero_duplicates(rows)
    assert_contiguous_coverage(rpc_url, rows, deploy.registry_address)

    # Scenario: Foreign logs are ignored (25 same-topic0 logs from another
    # contract were mined during this run). The foreign emitter is deployed by
    # the emit run, not the deploy-only run, so use its address.
    assert_foreign_logs_ignored(rpc_url, rows, run.foreign_address)

    # Scenario: Mint decodes as transfer from zero.
    assert_mint_decoded_from_zero(rows)

    # Scenarios: Compliance update decodes flag; payload exposes semantics + raw.
    assert_compliance_flags_are_native_booleans(rows)
    assert_raw_copy_verbatim(rpc_url, rows, deploy.registry_address)

    ChainApp.stop()
  end

  @tag timeout: 300_000
  test "killed listener resumes across restart boundary without gap or duplicate", %{
    rpc_url: rpc_url
  } do
    deploy = deploy_and_start(rpc_url)

    phase_one = emit(rpc_url, 1, deploy.registry_address)
    await_catchup(rpc_url, phase_one.expected_events)

    pre_restart = snapshot(all_rows())

    # Kill mid-run: supervisor (:rest_for_one) must restart the listener,
    # which resumes from the last persisted block.
    old_pid = Process.whereis(TokenLedger.ChainEventListener)
    Process.exit(old_pid, :kill)

    wait_until!(
      30_000,
      fn ->
        pid = Process.whereis(TokenLedger.ChainEventListener)
        pid != nil and pid != old_pid and Process.alive?(pid)
      end,
      "listener restarted by its supervisor"
    )

    phase_two = emit(rpc_url, 2, deploy.registry_address)
    total = phase_one.expected_events + phase_two.expected_events
    await_catchup(rpc_url, total)

    rows = all_rows()

    assert length(rows) == total
    assert_zero_duplicates(rows)
    assert_contiguous_coverage(rpc_url, rows, deploy.registry_address)

    # Scenario: previously persisted rows survive the kill untouched.
    post_restart = snapshot(rows)

    Enum.each(pre_restart, fn {id, identity} ->
      assert Map.get(post_restart, id) == identity
    end)

    ChainApp.stop()
  end

  @tag timeout: 300_000
  test "transient RPC outage retried, ingestion completes after recovery", %{rpc_url: rpc_url} do
    truncate_events()

    deploy = run_load_script(rpc_url, phase: 3)

    Application.put_env(
      :token_ledger,
      :contract_address,
      String.downcase(deploy.registry_address)
    )

    # Blind the app BEFORE emitting so events accumulate during the outage.
    Application.put_env(:token_ledger, :rpc_url, "http://127.0.0.1:1")
    ChainApp.start(deploy.registry_address)

    phase_one = emit(rpc_url, 1, deploy.registry_address)

    # Bounded negative check: while blind, nothing may reach the database.
    assert {:error, :timeout} =
             wait_until(6_000, fn -> row_count() > 0 end)

    assert row_count() == 0

    # Recover: ingestion resumes automatically (no manual nudge).
    Application.put_env(:token_ledger, :rpc_url, rpc_url)
    await_catchup(rpc_url, phase_one.expected_events)

    phase_two = emit(rpc_url, 2, deploy.registry_address)
    total = phase_one.expected_events + phase_two.expected_events
    await_catchup(rpc_url, total)

    rows = all_rows()

    assert length(rows) == total
    assert_zero_duplicates(rows)
    assert_contiguous_coverage(rpc_url, rows, deploy.registry_address)

    ChainApp.stop()
  end

  # ------------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------------

  defp deploy_and_start(rpc_url) do
    truncate_events()
    deploy = run_load_script(rpc_url, phase: 3)

    Application.put_env(
      :token_ledger,
      :contract_address,
      String.downcase(deploy.registry_address)
    )

    ChainApp.start(deploy.registry_address)
    deploy
  end

  defp emit(rpc_url, phase, registry_address) do
    run_load_script(rpc_url, phase: phase, registry: registry_address)
  end

  defp truncate_events do
    Repo.delete_all(TokenLedger.ChainEvents.Event)
  end

  defp all_rows do
    ChainEvents.list_events(@chain_id)
  end

  defp row_count do
    Repo.aggregate(TokenLedger.ChainEvents.Event, :count)
  end

  defp snapshot(rows) do
    Map.new(rows, &{&1.id, {&1.block_number, &1.log_index}})
  end

  defp await_catchup(rpc_url, expected_total) do
    case wait_until(@catchup_timeout, fn ->
           row_count() >= expected_total and caught_up?(rpc_url)
         end) do
      :ok ->
        :ok

      {:error, :timeout} ->
        flunk("catch-up deadline elapsed: persisted=#{row_count()} expected=#{expected_total}")
    end
  end

  defp caught_up?(rpc_url) do
    height = height!(rpc_url)
    next = safe_next_block()
    is_integer(next) and next > height
  end

  defp safe_next_block do
    GenServer.call(TokenLedger.ChainEventListener, :next_block)
  catch
    :exit, _ -> nil
  end

  defp assert_zero_duplicates(rows) do
    pairs = Enum.map(rows, &{&1.block_number, &1.log_index})
    assert pairs == Enum.uniq(pairs), "(block_number, log_index) duplicates found"
  end

  # The chain itself is the truth source: group its watched logs by block and
  # demand the database show exactly the same per-block picture — every block
  # containing watched events fully covered, none extra, none missing.
  defp assert_contiguous_coverage(rpc_url, rows, registry_address) do
    height = height!(rpc_url)
    {:ok, logs} = Client.get_logs(registry_address, 0, height)

    chain_blocks = per_block_counts(logs)
    db_blocks = per_block_counts(rows)

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

  defp assert_foreign_logs_ignored(rpc_url, rows, foreign_address) do
    height = height!(rpc_url)

    {:ok, foreign_logs} =
      logs(rpc_url, %{
        "address" => foreign_address,
        "fromBlock" => Client.integer_to_quantity(0),
        "toBlock" => Client.integer_to_quantity(height)
      })

    # Prove the harness genuinely created the hazard before asserting absence.
    assert Enum.count(foreign_logs) == 25

    foreign_pairs =
      MapSet.new(foreign_logs, fn log ->
        {Client.quantity_to_integer!(log["blockNumber"]),
         Client.quantity_to_integer!(log["logIndex"])}
      end)

    db_pairs = MapSet.new(rows, &{&1.block_number, &1.log_index})

    assert MapSet.disjoint?(foreign_pairs, db_pairs)
  end

  defp assert_mint_decoded_from_zero(rows) do
    mint_rows =
      Enum.filter(rows, fn row ->
        row.event_type == "transfer" and row.payload["from"] == @zero_address
      end)

    # 10 actors plus the owner, per LoadEvents.s.sol.
    assert Enum.count(mint_rows) == 11

    Enum.each(mint_rows, fn row ->
      assert Regex.match?(~r/\A\d+\z/, row.payload["amount"])
      assert byte_size(row.payload["to"]) == 42
      assert String.downcase(row.payload["to"]) == row.payload["to"]
    end)
  end

  defp assert_compliance_flags_are_native_booleans(rows) do
    compliance_rows = Enum.filter(rows, &(&1.event_type == "compliance_updated"))
    refute compliance_rows == []

    assert Enum.all?(compliance_rows, fn row ->
             is_boolean(row.payload["whitelisted"]) and row.payload["whitelisted"] == true
           end)
  end

  # Scenario: stored payload's raw sub-object matches the original log's
  # topics/data exactly — checked against a fresh read from the node.
  defp assert_raw_copy_verbatim(rpc_url, rows, registry_address) do
    height = height!(rpc_url)
    {:ok, logs} = Client.get_logs(registry_address, 0, height)

    by_identity =
      Map.new(logs, fn log ->
        {{Client.quantity_to_integer!(log["blockNumber"]),
          Client.quantity_to_integer!(log["logIndex"])}, log}
      end)

    sample = List.first(rows)
    log = Map.fetch!(by_identity, {sample.block_number, sample.log_index})

    assert sample.payload["raw"]["topics"] == log["topics"]
    assert sample.payload["raw"]["data"] == log["data"]
  end
end
