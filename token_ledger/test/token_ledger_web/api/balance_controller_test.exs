defmodule TokenLedgerWeb.Api.BalanceControllerTest do
  use TokenLedgerWeb.Api.ConnCase, async: false

  alias TokenLedger.Projections.Balance
  alias TokenLedger.Repo

  setup do
    Repo.delete_all(Balance)
    :ok
  end

  describe "GET /api/balance/:address" do
    test "returns the projected balance and as_of_block for a known address" do
      address = "0xknown"

      {:ok, _} =
        Repo.insert(%Balance{account_address: address, amount: Decimal.new("1234"), as_of_block: 42})

      conn = get(build_conn(), "/api/balance/#{address}")

      assert %{
               "address" => ^address,
               "balance" => "1234",
               "as_of_block" => 42
             } = json_response(conn, 200)
    end

    test "returns a zero balance and as_of_block 0 for an unknown address" do
      address = "0xunknown"

      conn = get(build_conn(), "/api/balance/#{address}")

      assert %{
               "address" => ^address,
               "balance" => "0",
               "as_of_block" => 0
             } = json_response(conn, 200)
    end
  end
end