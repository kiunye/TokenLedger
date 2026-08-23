defmodule TokenLedger.RPC.ConnectionPoolTest do
  use ExUnit.Case, async: true

  alias TokenLedger.RPC.ConnectionPool

  @fast_policy %{attempts: 5, base_ms: 1, max_ms: 2}

  describe "run_with_retries/2 (pure retry engine)" do
    test "returns the first success without retrying" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        ConnectionPool.run_with_retries(
          fn ->
            Agent.update(agent, &(&1 + 1))
            {:ok, :value}
          end,
          @fast_policy
        )

      assert result == {:ok, :value}
      assert Agent.get(agent, & &1) == 1
    end

    test "retries transient failures until success" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        ConnectionPool.run_with_retries(
          fn ->
            # Return the post-increment count: 1 and 2 fail, 3 succeeds.
            count = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

            if count < 3 do
              {:error, :econnrefused}
            else
              {:ok, :recovered}
            end
          end,
          @fast_policy
        )

      assert result == {:ok, :recovered}
      assert Agent.get(agent, & &1) == 3
    end

    test "exhausts attempts and returns the last error" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      result =
        ConnectionPool.run_with_retries(
          fn ->
            Agent.update(agent, &(&1 + 1))
            {:error, :timeout}
          end,
          %{attempts: 3, base_ms: 1, max_ms: 2}
        )

      assert result == {:error, :timeout}
      assert Agent.get(agent, & &1) == 3
    end
  end

  describe "execute/2" do
    # execute/2 addresses the pool under its production registered name (one
    # pool per node), so this test starts it exactly that way.
    test "runs a call under the configured policy and retries failures" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      start_supervised!({ConnectionPool, policy: %{attempts: 4, base_ms: 1, max_ms: 2}})

      result =
        ConnectionPool.execute(
          fn ->
            # Post-increment count: first call fails, second succeeds.
            count = Agent.get_and_update(agent, fn n -> {n + 1, n + 1} end)

            if count < 2 do
              {:error, :closed}
            else
              {:ok, %{"result" => "0x1"}}
            end
          end,
          :test_call
        )

      assert result == {:ok, %{"result" => "0x1"}}
      assert Agent.get(agent, & &1) == 2
    end
  end
end
