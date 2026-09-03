defmodule TokenLedgerWeb.Api.TransferController do
  @moduledoc """
  Simulates a token transfer without executing it on-chain.

  Checks the projected (confirmed-only) state to predict whether a transfer
  would succeed or revert. Returns success only if:
  1. The sender is whitelisted
  2. The recipient is whitelisted
  3. The sender has sufficient confirmed balance
  """

  use TokenLedgerWeb, :controller

  alias TokenLedger.Accounts.Account
  alias TokenLedger.Projections.Balance
  alias TokenLedger.Repo

  def simulate(conn, %{"from" => from, "to" => to, "amount" => amount_str}) do
    with {:ok, amount} <- parse_amount(amount_str),
         {:ok, _sender} <- check_whitelisted(from, :sender_not_whitelisted),
         {:ok, _recipient} <- check_whitelisted(to, :recipient_not_whitelisted),
         {:ok, _balance} <- check_balance(from, amount) do
      json(conn, %{
        "success" => true,
        "from" => from,
        "to" => to,
        "amount" => amount_str,
        "gas_used" => 52_000,
        "error" => nil
      })
    else
      {:error, :invalid_amount} ->
        json(conn, %{
          "success" => false,
          "error" => "Invalid amount: must be a positive decimal string"
        })

      {:error, :sender_not_whitelisted} ->
        json(conn, %{
          "success" => false,
          "error" => "Sender is not whitelisted"
        })

      {:error, :recipient_not_whitelisted} ->
        json(conn, %{
          "success" => false,
          "error" => "Recipient is not whitelisted"
        })

      {:error, :insufficient_balance} ->
        json(conn, %{
          "success" => false,
          "error" => "Insufficient balance"
        })
    end
  end

  defp parse_amount(amount_str) when is_binary(amount_str) do
    case Decimal.parse(amount_str) do
      {amount, ""} ->
        if Decimal.gt?(amount, 0), do: {:ok, amount}, else: {:error, :invalid_amount}
      _ ->
        {:error, :invalid_amount}
    end
  end
  defp parse_amount(_), do: {:error, :invalid_amount}

  defp check_whitelisted(address, error_atom) do
    case Repo.get(Account, address) do
      nil -> {:error, error_atom}
      account ->
        if account.whitelisted, do: {:ok, account}, else: {:error, error_atom}
    end
  end

  defp check_balance(address, amount) do
    case Repo.get(Balance, address) do
      nil -> {:error, :insufficient_balance}
      balance ->
        if Decimal.gte?(balance.amount, amount), do: {:ok, balance}, else: {:error, :insufficient_balance}
    end
  end
end