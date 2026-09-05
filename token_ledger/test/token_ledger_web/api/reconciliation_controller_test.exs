defmodule TokenLedgerWeb.Api.ReconciliationControllerTest do
  use TokenLedgerWeb.Api.ConnCase, async: false

  alias TokenLedger.ChainEvents
  alias TokenLedger.ChainEvents.Event
  alias TokenLedger.Reconciliation.Run
  alias TokenLedger.Repo
  import Ecto.Query

  @chain_id 99_999

  setup do
    Repo.delete_all(from(e in Event, where: e.chain_id == ^@chain_id))
    Repo.delete_all(from(r in Run, where: r.chain_id == ^@chain_id))
    :ok
  end

  defp event(block) do
    %{
      chain_id: @chain_id,
      block_number: block,
      block_hash: "0xhash#{block}",
      log_index: block,
      event_type: "transfer",
      payload: %{"amount" => "1", "raw" => %{"topics" => [], "data" => "0x"}}
    }
  end

  describe "GET /api/reconciliation/status" do
    test "returns synced status when chain head equals confirmed head" do
      {:ok, _} = ChainEvents.persist_events([event(5), event(6)])
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 6)

      conn = get(build_conn(), "/api/reconciliation/status")

      assert %{
               "chain_id" => 31337,
               "chain_head" => 6,
               "confirmed_head" => 6,
               "lag" => 0,
               "status" => "synced"
             } = json_response(conn, 200)
    end

    test "returns syncing status and positive lag when confirmed head trails chain head" do
      {:ok, _} = ChainEvents.persist_events([event(5), event(6), event(7)])
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 5)

      conn = get(build_conn(), "/api/reconciliation/status")

      assert %{
               "chain_head" => 7,
               "confirmed_head" => 5,
               "lag" => 2,
               "status" => "syncing"
             } = json_response(conn, 200)
    end

    test "returns null last_run when no reconciliation runs exist" do
      {:ok, _} = ChainEvents.persist_events([event(5)])
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 5)

      conn = get(build_conn(), "/api/reconciliation/status")

      assert %{"last_run" => nil} = json_response(conn, 200)
    end

    test "returns last_run info for the most recent run" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, _} = ChainEvents.persist_events([event(5)])
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 5)

      {:ok, run} =
        Repo.insert(%Run{
          chain_id: @chain_id,
          started_at: now,
          completed_at: now,
          chain_height_at_start: 5,
          indexed_height_at_start: 5,
          gap_blocks_backfilled: 2,
          reorg_detected: true
        })

      conn = get(build_conn(), "/api/reconciliation/status")

      assert %{"last_run" => last_run} = json_response(conn, 200)
      assert last_run["id"] == run.id
      assert last_run["gap_blocks_backfilled"] == 2
      assert last_run["reorg_detected"] == true
    end
  end
end