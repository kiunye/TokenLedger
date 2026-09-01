defmodule TokenLedgerWeb.AccountLive do
  @moduledoc """
  Account LiveView: per-address confirmed balance and event history.
  """

  use TokenLedgerWeb, :live_view

  @impl true
  def mount(%{"address" => address}, _session, socket) do
    {:ok, assign(socket, :address, address)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>Account {@address}</div>
    """
  end
end
