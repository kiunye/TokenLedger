defmodule TokenLedger.SupervisionShapeTest do
  use ExUnit.Case, async: true

  # Introspects the supervisors' init results directly: proves the locked
  # supervision shape (design decision 6 / architecture §4.3) without booting
  # any RPC machinery. Runtime recovery is proven by the integration suite.

  describe "TokenLedger.Sepolia.Supervisor" do
    test "rest_for_one with intensity 5 per 60s, pool before listener" do
      assert {:ok, {flags, children}} = TokenLedger.Sepolia.Supervisor.init([])

      # Supervisor.init normalizes to Erlang flag names.
      assert flags.strategy == :rest_for_one
      assert flags.intensity == 5
      assert flags.period == 60

      assert Enum.map(children, & &1.id) == [
               TokenLedger.RPC.ConnectionPool,
               TokenLedger.ChainEventListener
             ]

      # No explicit :restart key means the OTP default :permanent.
      assert Enum.all?(children, &(&1.restart in [nil, :permanent]))
    end
  end

  describe "TokenLedger.ChainSupervisor" do
    test "one_for_one over the per-chain subtree" do
      assert {:ok, {flags, children}} = TokenLedger.ChainSupervisor.init([])

      assert flags.strategy == :one_for_one

      assert Enum.map(children, & &1.id) == [TokenLedger.Sepolia.Supervisor]
    end
  end
end
