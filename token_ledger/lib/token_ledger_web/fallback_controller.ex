defmodule TokenLedgerWeb.FallbackController do
  @behaviour Plug.Controller

  def call(conn, {:ok, result}) do
    result
  end

  def call(conn, {:error, reason}) do
    json(conn, %{error: reason}, 500)
  end
end