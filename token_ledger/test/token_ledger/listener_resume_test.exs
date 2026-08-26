defmodule TokenLedger.ListenerResumeTest do
  # Unit-level proof of the §4.3 resume contract: the listener derives its
  # initial cursor from the last *confirmed* block, not the last persisted one.
  use ExUnit.Case, async: false

  alias TokenLedger.ChainEventListener
  alias TokenLedger.ChainEvents
  alias TokenLedger.Repo
  import Ecto.Query

  @chain_id 93_001

  setup do
    Repo.delete_all(from(e in ChainEvents.Event, where: e.chain_id == ^@chain_id))
    Repo.delete_all(TokenLedger.Projections.Balance)
    Repo.delete_all(TokenLedger.Accounts.Account)
    Repo.delete_all(from(c in TokenLedger.Projections.Checkpoint, where: c.chain_id == ^@chain_id))
    :ok
  end

  defp event(block, log_index, payload) do
    %{
      chain_id: @chain_id,
      block_number: block,
      block_hash: "0xh#{block}",
      log_index: log_index,
      event_type: "transfer",
      payload: payload
    }
  end

  describe "ChainEventListener resume cursor (§4.3)" do
    test "resumes at last_confirmed_block + 1 when events are confirmed" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(1, 0, %{"from" => "0x0", "to" => "0xa", "amount" => "100", "raw" => %{}}),
          event(2, 0, %{"from" => "0xa", "to" => "0xb", "amount" => "40", "raw" => %{}})
        ])

      {:ok, 2} = ChainEvents.confirm_through(@chain_id, 2)

      assert ChainEventListener.resume_cursor(@chain_id) == 3
    end

    test "falls back to start_block when nothing is confirmed" do
      {:ok, _} =
        ChainEvents.persist_events([
          event(1, 0, %{"from" => "0x0", "to" => "0xa", "amount" => "100", "raw" => %{}})
        ])

      # Persisted but unconfirmed: resume must not skip past it via the
      # persisted watermark; it keys off confirmation, so it starts fresh.
      assert ChainEventListener.resume_cursor(@chain_id) == 0
    end

    test "empty log resumes at start_block" do
      assert ChainEventListener.resume_cursor(@chain_id) == 0
    end
  end

  describe "ProjectionWorker placement (§4.3)" do
    test "fourth permanent child after the reorg watcher" do
      {:ok, {_flags, children}} = TokenLedger.Sepolia.Supervisor.init([])

      assert Enum.map(children, & &1.id) == [
               TokenLedger.RPC.ConnectionPool,
               TokenLedger.ChainEventListener,
               TokenLedger.ReorgWatcher,
               TokenLedger.ProjectionWorker
             ]
    end
  end
end
