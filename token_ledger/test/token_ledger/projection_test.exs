defmodule TokenLedger.ProjectionTest do
  # Touches the shared test database; serialized against the integration suite.
  use ExUnit.Case, async: false

  alias TokenLedger.Accounts.Account
  alias TokenLedger.ChainEvents
  alias TokenLedger.Projection
  alias TokenLedger.Projections.Balance
  alias TokenLedger.Repo
  import Ecto.Query

  @chain_id 92_001
  @zero "0x0000000000000000000000000000000000000000"

  setup do
    Repo.delete_all(from(e in ChainEvents.Event, where: e.chain_id == ^@chain_id))
    Repo.delete_all(Balance)
    Repo.delete_all(Account)
    Repo.delete_all(from(c in TokenLedger.Projections.Checkpoint, where: c.chain_id == ^@chain_id))
    :ok
  end

  defp persist_and_confirm(events, through_block \\ 1_000_000) do
    {:ok, _} = ChainEvents.persist_events(events)
    {:ok, _} = ChainEvents.confirm_through(@chain_id, through_block)
  end

  defp mint(to, amount, block, log_index) do
    transfer(@zero, to, amount, block, log_index)
  end

  defp transfer(from, to, amount, block, log_index) do
    %{
      chain_id: @chain_id,
      block_number: block,
      block_hash: "0xh#{block}",
      log_index: log_index,
      event_type: "transfer",
      payload: %{
        "from" => from,
        "to" => to,
        "amount" => amount,
        "raw" => %{"topics" => [], "data" => "0x"}
      }
    }
  end

  defp compliance(account, whitelisted, block, log_index) do
    %{
      chain_id: @chain_id,
      block_number: block,
      block_hash: "0xh#{block}",
      log_index: log_index,
      event_type: "compliance_updated",
      payload: %{
        "account" => account,
        "whitelisted" => whitelisted,
        "raw" => %{"topics" => [], "data" => "0x"}
      }
    }
  end

  defp balance_of(address) do
    case Repo.get(Balance, address) do
      nil -> Decimal.new(0)
      %{amount: amount} -> amount
    end
  end

  defp whitelisted?(address) do
    case Repo.get(Account, address) do
      nil -> nil
      %{whitelisted: w} -> w
    end
  end

  describe "apply_batch/2" do
    test "mint credits the recipient and materializes the account, never the zero address" do
      persist_and_confirm([mint("0xa", "1000", 1, 0)])

      assert {:ok, 1, _cursor} = Projection.apply_batch(@chain_id, 500)
      assert Decimal.equal?(balance_of("0xa"), Decimal.new(1000))
      assert whitelisted?("0xa") == false
      assert Repo.get(Account, @zero) == nil
      assert Repo.get(Balance, @zero) == nil
    end

    test "transfer debits sender and credits recipient; repeated application is a no-op (idempotent)" do
      persist_and_confirm([
        mint("0xa", "1000", 1, 0),
        transfer("0xa", "0xb", "300", 2, 0)
      ])

      assert {:ok, 2, _} = Projection.apply_batch(@chain_id, 500)
      assert Decimal.equal?(balance_of("0xa"), Decimal.new(700))
      assert Decimal.equal?(balance_of("0xb"), Decimal.new(300))

      # Second pass over the same confirmed range: nothing new, state identical.
      assert {:ok, 0, _} = Projection.apply_batch(@chain_id, 500)
      assert Decimal.equal?(balance_of("0xa"), Decimal.new(700))
      assert Decimal.equal?(balance_of("0xb"), Decimal.new(300))
    end

    test "compliance_updated mirrors whitelist without touching balances" do
      persist_and_confirm([
        mint("0xa", "1000", 1, 0),
        compliance("0xa", true, 2, 0),
        compliance("0xb", true, 2, 1)
      ])

      assert {:ok, 3, _} = Projection.apply_batch(@chain_id, 500)
      assert whitelisted?("0xa") == true
      assert whitelisted?("0xb") == true
      # Balance unaffected by compliance events.
      assert Decimal.equal?(balance_of("0xa"), Decimal.new(1000))
    end

    test "as_of_block records the last block that touched each account" do
      persist_and_confirm([
        mint("0xa", "1000", 1, 0),
        transfer("0xa", "0xb", "300", 5, 0)
      ])

      Projection.apply_batch(@chain_id, 500)

      assert Repo.get(Balance, "0xa").as_of_block == 5
      assert Repo.get(Balance, "0xb").as_of_block == 5
    end

    test "ignores unconfirmed events entirely" do
      {:ok, _} =
        ChainEvents.persist_events([
          mint("0xa", "1000", 1, 0)
        ])

      assert {:ok, 0, _} = Projection.apply_batch(@chain_id, 500)
      assert Repo.get(Balance, "0xa") == nil
    end

    test "applies in log order across batches, advancing the checkpoint" do
      persist_and_confirm([
        mint("0xa", "1000", 1, 0),
        transfer("0xa", "0xb", "100", 2, 0),
        mint("0xc", "50", 3, 0)
      ])

      assert {:ok, 2, _} = Projection.apply_batch(@chain_id, 2)
      assert Decimal.equal?(balance_of("0xa"), Decimal.new(900))
      assert Decimal.equal?(balance_of("0xb"), Decimal.new(100))
      # Third event not yet applied.
      assert Repo.get(Balance, "0xc") == nil

      assert {:ok, 1, _} = Projection.apply_batch(@chain_id, 2)
      assert Decimal.equal?(balance_of("0xc"), Decimal.new(50))
    end
  end

  describe "rebuild/1 equivalence" do
    test "rebuild from zero yields identical state to incremental application" do
      events = [
        mint("0xa", "1000", 1, 0),
        compliance("0xa", true, 2, 0),
        transfer("0xa", "0xb", "400", 3, 0),
        mint("0xc", "77", 4, 0),
        compliance("0xb", true, 5, 0),
        transfer("0xb", "0xa", "50", 6, 0)
      ]

      persist_and_confirm(events)

      {:ok, _, _} = Projection.apply_batch(@chain_id, 500)

      incremental =
        %{
          balances: balances_snapshot(),
          accounts: accounts_snapshot()
        }

      {:ok, _} = Projection.rebuild(@chain_id)

      rebuilt =
        %{
          balances: balances_snapshot(),
          accounts: accounts_snapshot()
        }

      assert rebuilt == incremental
      assert Decimal.equal?(balance_of("0xa"), Decimal.new(650))
      assert Decimal.equal?(balance_of("0xb"), Decimal.new(350))
      assert Decimal.equal?(balance_of("0xc"), Decimal.new(77))
      assert whitelisted?("0xa") == true
      assert whitelisted?("0xb") == true
    end
  end

  defp balances_snapshot do
    Balance
    |> Repo.all()
    |> Enum.map(fn b -> {b.account_address, Decimal.to_string(b.amount), b.as_of_block} end)
    |> Enum.sort()
  end

  defp accounts_snapshot do
    Account
    |> Repo.all()
    |> Enum.map(fn a -> {a.address, a.whitelisted} end)
    |> Enum.sort()
  end
end
