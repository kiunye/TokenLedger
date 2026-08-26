defmodule TokenLedger.Sepolia.Supervisor do
  @moduledoc """
  Per-chain subtree for the one chain this build targets (architecture §4.3).

  `:rest_for_one` with restart intensity 5 per 60s: `RPC.ConnectionPool`
  starts first, so if it dies the event listener and reorg watcher are torn
  down and restarted with it instead of limping on a dead connection; the
  watcher also restarts when only the listener dies, since its remembered
  tip hashes are stale after any rewind. A genuinely dead endpoint escalates
  past this supervisor rather than retrying forever. Later phases append
  `ProjectionWorker` as a child without reshaping.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(_opts) do
    children = [
      %{
        id: TokenLedger.RPC.ConnectionPool,
        start: {TokenLedger.RPC.ConnectionPool, :start_link, []},
        restart: :permanent
      },
      %{
        id: TokenLedger.ChainEventListener,
        start: {TokenLedger.ChainEventListener, :start_link, []},
        restart: :permanent
      },
      %{
        id: TokenLedger.ReorgWatcher,
        start: {TokenLedger.ReorgWatcher, :start_link, []},
        restart: :permanent
      }
    ]

    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 5, max_seconds: 60)
  end
end
