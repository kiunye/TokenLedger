defmodule TokenLedger.ReconciliationJobTest do
  # Unit proof of the reconciliation pass logic with an injected chain height
  # (no live RPC). The Oban cron wiring is verified separately by reading the
  # dev config (ReconciliationConfigTest).
  use ExUnit.Case, async: false

  alias TokenLedger.ChainEvents
  alias TokenLedger.Reconciliation
  alias TokenLedger.ReconciliationJob
  alias TokenLedger.Reconciliation.Run
  alias TokenLedger.Repo
  import Ecto.Query

  @chain_id 94_001

  setup do
    Repo.delete_all(from(e in ChainEvents.Event, where: e.chain_id == ^@chain_id))
    Repo.delete_all(from(r in Run, where: r.chain_id == ^@chain_id))
    Repo.delete_all(from(re in TokenLedger.ReorgEvents.ReorgEvent, where: re.chain_id == ^@chain_id))
    :ok
  end

  defp persisted_at(block) do
    {:ok, _} =
      ChainEvents.persist_events([
        %{
          chain_id: @chain_id,
          block_number: block,
          block_hash: "0xh#{block}",
          log_index: 0,
          event_type: "transfer",
          payload: %{"from" => "0x0", "to" => "0xa", "amount" => "1", "raw" => %{}}
        }
      ])
  end

  describe "run/2" do
    test "records a gap and nudges the listener when the indexer is behind" do
      persisted_at(10)
      # Live watermark at block 10, but the chain is at 25.
      ReconciliationJob.run(@chain_id, height: {:ok, 25})

      [run] = Repo.all(from(r in Run, where: r.chain_id == ^@chain_id))
      assert run.chain_height_at_start == 25
      assert run.indexed_height_at_start == 10
      assert run.gap_blocks_backfilled == 15
      assert not is_nil(run.completed_at)
      assert run.reorg_detected == false
    end

    test "records zero gap when caught up" do
      persisted_at(25)
      ReconciliationJob.run(@chain_id, height: {:ok, 25})

      [run] = Repo.all(from(r in Run, where: r.chain_id == ^@chain_id))
      assert run.gap_blocks_backfilled == 0
    end

    test "failed height read still records a gap-0 run rather than looping" do
      persisted_at(10)
      ReconciliationJob.run(@chain_id, height: {:error, :rpc_unavailable})

      [run] = Repo.all(from(r in Run, where: r.chain_id == ^@chain_id))
      assert run.gap_blocks_backfilled == 0
      assert not is_nil(run.completed_at)
      assert run.reorg_detected == false
    end
  end

  describe "Reconciliation.reorg_in_window?/3" do
    test "true when a reorg detection falls inside the window" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Insert a reorg event directly through the context.
      {:ok, _} =
        TokenLedger.ReorgEvents.record_detection(%{
          chain_id: @chain_id,
          fork_block: 5,
          depth: 1,
          events_orphaned: 1
        })

      # record_detection stamps detected_at at "now"; window [now-1s, now+1s].
      assert Reconciliation.reorg_in_window?(
               @chain_id,
               DateTime.add(now, -1, :second),
               DateTime.add(now, 1, :second)
             ) == true
    end

    test "false when no reorg in the window" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      assert Reconciliation.reorg_in_window?(
               @chain_id,
               DateTime.add(now, -10, :second),
               DateTime.add(now, -5, :second)
             ) == false
    end
  end
end
