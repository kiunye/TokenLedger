defmodule TokenLedgerWeb.FallbackController do
  use TokenLedgerWeb, :controller

  def call(conn, {:ok, result}) do
    result
  end

  def call(conn, {:error, reason}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{error: reason})
  end
end