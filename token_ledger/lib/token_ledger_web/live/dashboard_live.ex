defmodule TokenLedgerWeb.DashboardLive do
  @moduledoc """
  Dashboard LiveView: confirmed balances and chain head overview.
  """

  use TokenLedgerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>Dashboard</div>
    """
  end
end
