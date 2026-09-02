defmodule TokenLedger.ChainEventsTest do
  # Touches the shared test database; serialized against the integration
  # suite (all DB-writing cases are non-async).
  use ExUnit.Case, async: false

  alias TokenLedger.ChainEvents
  alias TokenLedger.Repo
  import Ecto.Query

  @chain_id 91_001

  setup do
    Repo.delete_all(from(e in ChainEvents.Event, where: e.chain_id == ^@chain_id))
    :ok
  end

  describe "persist_events/2" do
    test "inserts new rows and returns the inserted count" do
      assert {:ok, 3} = ChainEvents.persist_events(three_events())
      assert Enum.count(ChainEvents.list_events(@chain_id)) == 3
    end

    test "overlapping re-fetch of a persisted range is a no-op (spec: idempotent replay)" do
      {:ok, _} = ChainEvents.persist_events(three_events())

      assert {:ok, 0} = ChainEvents.persist_events(three_events())
      assert Enum.count(ChainEvents.list_events(@chain_id)) == 3
    end

    test "partial overlap inserts only genuinely new rows" do
      {:ok, _} = ChainEvents.persist_events(three_events())

      overlap = [
        event(1),
        event(2),
        event(3, log_index: 9_999)
      ]

      assert {:ok, 1} = ChainEvents.persist_events(overlap)
      assert Enum.count(ChainEvents.list_events(@chain_id)) == 4
    end

    test "duplicates within one batch cannot trip on themselves" do
      duplicated = three_events() ++ three_events()

      assert {:ok, 3} = ChainEvents.persist_events(duplicated)
      assert Enum.count(ChainEvents.list_events(@chain_id)) == 3
    end

    test "rows persist with confirmed/orphaned false and decoded payload intact" do
      payload = %{
        "from" => "0x0000000000000000000000000000000000000000",
        "to" => "0xabc",
        "amount" => "1000",
        "raw" => %{"topics" => ["0xdd"], "data" => "0x00"}
      }

      {:ok, _} =
        ChainEvents.persist_events([
          event(5, event_type: "transfer", payload: payload)
        ])

      [row] = ChainEvents.list_events(@chain_id)

      assert row.confirmed == false
      assert row.orphaned == false
      assert row.payload["amount"] == "1000"
      assert row.payload["raw"]["data"] == "0x00"
      assert %DateTime{} = row.inserted_at
    end
  end

  describe "max_persisted_block/1" do
    test "returns nil when nothing persisted for the chain" do
      assert ChainEvents.max_persisted_block(@chain_id) == nil
    end

    test "returns the highest block number regardless of insert order" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(10),
          event(4),
          event(7)
        ])

      assert ChainEvents.max_persisted_block(@chain_id) == 10
    end

    test "excludes orphaned rows so the resume cursor cannot sit on a phantom tip" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(10),
          event(11),
          event(12)
        ])

      {:ok, 2} = ChainEvents.mark_range_orphaned(@chain_id, 11, 12)

      assert ChainEvents.max_persisted_block(@chain_id) == 10
    end
  end

  describe "partial unique index (spec: chain_events idempotent replay post-orphan)" do
    test "canonical replacement inserts beside the orphaned row at the same identity" do
      {:ok, 1} = ChainEvents.persist_events([event(7, block_hash: "0xold")])
      {:ok, 1} = ChainEvents.mark_range_orphaned(@chain_id, 7, 7)

      assert {:ok, 1} = ChainEvents.persist_events([event(7, block_hash: "0xnew")])

      rows = ChainEvents.list_events(@chain_id)
      assert Enum.count(rows) == 2
      by_hash = Map.new(rows, &{&1.block_hash, &1})
      assert by_hash["0xold"].orphaned == true
      assert by_hash["0xnew"].orphaned == false
    end

    test "live duplicates still conflict-nothing" do
      {:ok, 1} = ChainEvents.persist_events([event(7)])

      assert {:ok, 0} = ChainEvents.persist_events([event(7, block_hash: "0xdifferent-hash-same-slot")])
      assert Enum.count(ChainEvents.list_events(@chain_id)) == 1
    end
  end

  describe "mark_range_orphaned/3" do
    test "marks only live rows in range and reports the count" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(1),
          event(2),
          event(3),
          event(4)
        ])

      assert {:ok, 2} = ChainEvents.mark_range_orphaned(@chain_id, 2, 3)

      rows = ChainEvents.list_events(@chain_id)
      orphaned = rows |> Enum.filter(& &1.orphaned) |> Enum.map(& &1.block_number) |> Enum.sort()
      assert orphaned == [2, 3]
    end

    test "is idempotent over an already-orphaned range" do
      {:ok, _} = ChainEvents.persist_events([event(2)])

      assert {:ok, 1} = ChainEvents.mark_range_orphaned(@chain_id, 1, 5)
      assert {:ok, 0} = ChainEvents.mark_range_orphaned(@chain_id, 1, 5)
    end
  end

  describe "confirm_through/2 (confirmation sweep)" do
    test "confirms live unconfirmed rows at or under the boundary only" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(10),
          event(11),
          event(12)
        ])

      assert {:ok, 2} = ChainEvents.confirm_through(@chain_id, 11)

      rows = ChainEvents.list_events(@chain_id)
      confirmed = rows |> Enum.filter(& &1.confirmed) |> Enum.map(& &1.block_number) |> Enum.sort()
      assert confirmed == [10, 11]
    end

    test "never confirms orphaned rows" do
      {:ok, _} = ChainEvents.persist_events([event(10), event(11)])
      {:ok, 1} = ChainEvents.mark_range_orphaned(@chain_id, 11, 11)

      assert {:ok, 1} = ChainEvents.confirm_through(@chain_id, 100)

      rows = ChainEvents.list_events(@chain_id)
      assert Enum.find(rows, &(&1.block_number == 10)).confirmed == true
      assert Enum.find(rows, &(&1.block_number == 11)).confirmed == false
    end
  end

  describe "live_block_hashes/3" do
    test "returns one hash per live block in range, excluding orphans" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(5, block_hash: "0xa", log_index: 0),
          event(5, block_hash: "0xa", log_index: 1),
          event(6, block_hash: "0xb", log_index: 0),
          event(7, block_hash: "0xcorphan", log_index: 0)
        ])

      {:ok, 1} = ChainEvents.mark_range_orphaned(@chain_id, 7, 7)

      assert ChainEvents.live_block_hashes(@chain_id, 5, 10) == %{5 => "0xa", 6 => "0xb"}
    end
  end

  describe "list_confirmed_events/2" do
    test "returns only confirmed, non-orphaned events in descending order" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(10, log_index: 0),
          event(11, log_index: 0),
          event(12, log_index: 0),
          event(13, log_index: 0)
        ])

      # Confirm blocks 10-11, orphan block 12
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 11)
      {:ok, _} = ChainEvents.mark_range_orphaned(@chain_id, 12, 12)

      events = ChainEvents.list_confirmed_events(@chain_id, limit: 10)

      assert length(events) == 2
      assert Enum.map(events, & &1.block_number) == [11, 10]
      assert Enum.all?(events, & &1.confirmed)
      assert Enum.all?(events, &(not &1.orphaned))
    end

    test "respects the limit parameter" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(1, log_index: 0),
          event(2, log_index: 0),
          event(3, log_index: 0)
        ])

      {:ok, _} = ChainEvents.confirm_through(@chain_id, 100)

      events = ChainEvents.list_confirmed_events(@chain_id, limit: 2)
      assert length(events) == 2
    end

    test "caps limit at 100" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(1, log_index: 0)
        ])

      {:ok, _} = ChainEvents.confirm_through(@chain_id, 100)

      # Should not raise, just cap at 100
      events = ChainEvents.list_confirmed_events(@chain_id, limit: 200)
      assert length(events) == 1
    end

    test "returns empty list when no confirmed events exist" do
      {:ok, _} = ChainEvents.persist_events([event(1, log_index: 0)])

      events = ChainEvents.list_confirmed_events(@chain_id, limit: 10)
      assert events == []
    end
  end

  describe "list_confirmed_events_for_address/3" do
    test "returns confirmed transfer events where address is sender or recipient" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(1,
            log_index: 0,
            event_type: "transfer",
            payload: %{
              "from" => "0xalice",
              "to" => "0xbob",
              "amount" => "100"
            }
          ),
          event(2,
            log_index: 0,
            event_type: "transfer",
            payload: %{
              "from" => "0xbob",
              "to" => "0xcharlie",
              "amount" => "50"
            }
          ),
          event(3,
            log_index: 0,
            event_type: "transfer",
            payload: %{
              "from" => "0xdave",
              "to" => "0xalice",
              "amount" => "200"
            }
          )
        ])

      {:ok, _} = ChainEvents.confirm_through(@chain_id, 100)

      # Query for 0xbob: should get events from block 1 (to) and block 2 (from)
      events = ChainEvents.list_confirmed_events_for_address(@chain_id, "0xbob", limit: 10)

      assert length(events) == 2
      block_numbers = Enum.map(events, & &1.block_number) |> Enum.sort()
      assert block_numbers == [1, 2]
    end

    test "does not return unconfirmed events" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(1,
            log_index: 0,
            event_type: "transfer",
            payload: %{"from" => "0xalice", "to" => "0xbob", "amount" => "100"}
          ),
          event(2,
            log_index: 0,
            event_type: "transfer",
            payload: %{"from" => "0xbob", "to" => "0xcharlie", "amount" => "50"}
          )
        ])

      # Only confirm block 1
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 1)

      events = ChainEvents.list_confirmed_events_for_address(@chain_id, "0xbob", limit: 10)
      assert length(events) == 1
      assert hd(events).block_number == 1
    end

    test "does not return non-transfer events" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(1,
            log_index: 0,
            event_type: "compliance_updated",
            payload: %{"account" => "0xbob", "whitelisted" => true}
          ),
          event(2,
            log_index: 0,
            event_type: "transfer",
            payload: %{"from" => "0xbob", "to" => "0xcharlie", "amount" => "50"}
          )
        ])

      {:ok, _} = ChainEvents.confirm_through(@chain_id, 100)

      events = ChainEvents.list_confirmed_events_for_address(@chain_id, "0xbob", limit: 10)
      assert length(events) == 1
      assert hd(events).event_type == "transfer"
    end
  end

  describe "confirmed_summary/1" do
    test "returns chain_head and confirmed_head" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(10, log_index: 0),
          event(11, log_index: 0),
          event(12, log_index: 0)
        ])

      {:ok, _} = ChainEvents.confirm_through(@chain_id, 11)

      summary = ChainEvents.confirmed_summary(@chain_id)
      assert summary.chain_head == 12
      assert summary.confirmed_head == 11
    end

    test "returns nils when no events exist" do
      summary = ChainEvents.confirmed_summary(@chain_id)
      assert summary.chain_head == nil
      assert summary.confirmed_head == nil
    end
  end

  defp three_events do
    [event(1), event(2), event(3)]
  end

  defp event(block_number, opts \\ []) do
    %{
      chain_id: @chain_id,
      block_number: block_number,
      block_hash: Keyword.get(opts, :block_hash, "0xhash#{block_number}"),
      log_index: Keyword.get(opts, :log_index, block_number),
      event_type: Keyword.get(opts, :event_type, "transfer"),
      payload:
        Keyword.get(opts, :payload, %{"amount" => "1", "raw" => %{"topics" => [], "data" => "0x"}})
    }
  end
end
