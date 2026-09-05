defmodule TokenLedgerWeb.Api.EventControllerTest do
  use TokenLedgerWeb.Api.ConnCase, async: false

  alias TokenLedger.ChainEvents
  alias TokenLedger.ChainEvents.Event
  alias TokenLedger.Repo
  import Ecto.Query

  @chain_id 99_999

  setup do
    Repo.delete_all(from(e in Event, where: e.chain_id == ^@chain_id))
    :ok
  end

  defp event(block, opts \\ []) do
    %{
      chain_id: @chain_id,
      block_number: block,
      block_hash: Keyword.get(opts, :block_hash, "0xhash#{block}"),
      log_index: Keyword.get(opts, :log_index, block),
      event_type: Keyword.get(opts, :event_type, "transfer"),
      payload: Keyword.get(opts, :payload, %{"amount" => "1", "raw" => %{"topics" => [], "data" => "0x"}})
    }
  end

  defp persist(events), do: {:ok, _} = ChainEvents.persist_events(events)

  describe "GET /api/events" do
    test "returns confirmed, non-orphaned events in descending order" do
      persist([event(10), event(11), event(12)])
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 12)

      conn = get(build_conn(), "/api/events")

      events = json_response(conn, 200)
      block_numbers = Enum.map(events, & &1["block_number"])

      assert block_numbers == [12, 11, 10]
      assert Enum.all?(events, & &1["confirmed"])
    end

    test "respects ?limit=N" do
      persist([event(10), event(11), event(12)])
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 12)

      conn = get(build_conn(), "/api/events?limit=1")

      events = json_response(conn, 200)
      assert length(events) == 1
      assert hd(events)["block_number"] == 12
    end

    test "clamps an oversized limit to the default of 20" do
      persist(Enum.map(1..25, &event/1))
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 25)

      conn = get(build_conn(), "/api/events?limit=999")

      events = json_response(conn, 200)
      assert length(events) == 20
    end

    test "returns an empty list when no events exist" do
      conn = get(build_conn(), "/api/events")

      assert json_response(conn, 200) == []
    end

    test "does not return orphaned events" do
      persist([event(10), event(11), event(12)])
      # Orphan block 12 *before* confirming: an orphaned row can never be
      # confirmed, so the endpoint must exclude it entirely.
      {:ok, _} = ChainEvents.mark_range_orphaned(@chain_id, 12, 12)
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 11)

      conn = get(build_conn(), "/api/events")

      events = json_response(conn, 200)
      block_numbers = Enum.map(events, & &1["block_number"])

      assert block_numbers == [11, 10]
    end
  end
end