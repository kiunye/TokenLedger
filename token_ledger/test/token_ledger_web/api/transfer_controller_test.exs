defmodule TokenLedgerWeb.Api.TransferControllerTest do
  use TokenLedgerWeb.Api.ConnCase, async: false

  alias TokenLedger.Accounts.Account
  alias TokenLedger.Projections.Balance
  alias TokenLedger.Repo

  @sender "0x0000000000000000000000000000000000000001"
  @recipient "0x0000000000000000000000000000000000000002"

  setup do
    Repo.delete_all(Account)
    Repo.delete_all(Balance)
    :ok
  end

  defp insert_whitelisted(address, whitelisted \\ true) do
    {:ok, _} = Repo.insert(%Account{address: address, whitelisted: whitelisted, role: "investor"})
  end

  defp insert_balance(address, amount_str) do
    {:ok, _} =
      Repo.insert(%Balance{
        account_address: address,
        amount: Decimal.new(amount_str),
        as_of_block: 10
      })
  end

  defp simulate(from, to, amount) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> post("/api/transfers/simulate", Jason.encode!(%{"from" => from, "to" => to, "amount" => amount}))
  end

  describe "POST /api/transfers/simulate" do
    test "succeeds when sender and recipient are whitelisted and balance is sufficient" do
      insert_whitelisted(@sender)
      insert_whitelisted(@recipient)
      insert_balance(@sender, "100")

      conn = simulate(@sender, @recipient, "40")

      assert %{
               "success" => true,
               "from" => @sender,
               "to" => @recipient,
               "amount" => "40",
               "error" => nil
             } = json_response(conn, 200)
    end

    test "fails when the amount is not a positive decimal" do
      insert_whitelisted(@sender)
      insert_whitelisted(@recipient)
      insert_balance(@sender, "100")

      for bad_amount <- ["0", "-5", "abc", ""] do
        conn = simulate(@sender, @recipient, bad_amount)
        assert %{"success" => false, "error" => _} = json_response(conn, 200)
      end
    end

    test "fails when the sender is not whitelisted" do
      insert_whitelisted(@sender, false)
      insert_whitelisted(@recipient)
      insert_balance(@sender, "100")

      conn = simulate(@sender, @recipient, "40")

      assert %{
               "success" => false,
               "error" => "Sender is not whitelisted"
             } = json_response(conn, 200)
    end

    test "fails when the recipient is not whitelisted" do
      insert_whitelisted(@sender)
      insert_whitelisted(@recipient, false)
      insert_balance(@sender, "100")

      conn = simulate(@sender, @recipient, "40")

      assert %{
               "success" => false,
               "error" => "Recipient is not whitelisted"
             } = json_response(conn, 200)
    end

    test "fails when the sender has insufficient balance" do
      insert_whitelisted(@sender)
      insert_whitelisted(@recipient)
      insert_balance(@sender, "10")

      conn = simulate(@sender, @recipient, "40")

      assert %{
               "success" => false,
               "error" => "Insufficient balance"
             } = json_response(conn, 200)
    end

    test "fails when the recipient does not exist" do
      insert_whitelisted(@sender)
      insert_balance(@sender, "100")

      conn = simulate(@sender, @recipient, "40")

      assert %{
               "success" => false,
               "error" => "Recipient is not whitelisted"
             } = json_response(conn, 200)
    end
  end
end