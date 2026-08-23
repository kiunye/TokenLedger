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
