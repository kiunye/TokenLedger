defmodule TokenLedger.Test.ChainApp do
  @moduledoc """
  Starts and stops the REAL production supervision tree
  (`TokenLedger.ChainSupervisor` → `Sepolia.Supervisor` → pool + listener)
  detached from ExUnit's per-test processes, so restart behavior can be
  observed exactly as it happens in production.

  The holder is a plain unlinked GenServer: the tree it owns must not die
  when a test process finishes. Contract address comes from application env,
  same as production (`config/runtime.exs` in dev).
  """

  use GenServer

  alias TokenLedger.ChainSupervisor
  alias TokenLedger.Test.Harness

  def start(contract_address) do
    stop()
    Application.put_env(:token_ledger, :contract_address, String.downcase(contract_address))
    # Pin the integration chain so the listener (whose `init/1` reads
    # `ChainConfig.chain_id/0` once and caches it) cannot pick up a value
    # left behind by a concurrently-running controller test, which routes
    # HTTP requests to a different chain to isolate fixture deletes.
    Application.put_env(:token_ledger, :chain_id, 31_337)

    case GenServer.start(__MODULE__, :ok, name: __MODULE__) do
      {:ok, _holder} -> :ok
      {:error, reason} -> raise "ChainApp failed to boot supervision tree: #{inspect(reason)}"
    end
  end

  @doc "Stops the tree (children first) and the holder. Idempotent."
  def stop do
    case GenServer.whereis(__MODULE__) do
      nil -> stop_leaked_tree()
      pid -> safe_call_stop(pid)
    end

    wait_for_teardown()
    :ok
  end

  # Holder alive but tree already gone, or vice versa — cover both shapes.
  defp safe_call_stop(pid) do
    GenServer.stop(pid, :normal)
    stop_leaked_tree()
  end

  defp stop_leaked_tree do
    case Process.whereis(ChainSupervisor) do
      nil -> :ok
      sup -> Supervisor.stop(sup, :normal)
    end
  rescue
    _ -> :ok
  end

  # The supervisor's children unregister their names synchronously during
  # shutdown, but give the BEAM a beat so the next start cannot race a dying
  # registration.
  defp wait_for_teardown do
    Harness.wait_until!(
      10_000,
      fn ->
        Process.whereis(ChainSupervisor) == nil and
          Process.whereis(TokenLedger.RPC.ConnectionPool) == nil and
          Process.whereis(TokenLedger.ChainEventListener) == nil and
          Process.whereis(TokenLedger.ReorgWatcher) == nil
      end,
      "chain supervision tree fully stopped"
    )
  end

  @impl true
  def init(:ok) do
    {:ok, sup} = ChainSupervisor.start_link()
    {:ok, %{supervisor: sup}}
  end

  @impl true
  def terminate(_reason, %{supervisor: sup}) do
    Supervisor.stop(sup, :normal)
  rescue
    _ -> :ok
  end
end
