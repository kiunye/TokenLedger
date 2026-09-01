defmodule TokenLedgerWeb.AdminLive do
  @moduledoc """
  Admin LiveView: compliance workflow management.
  """

  use TokenLedgerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>Admin</div>
    """
  end
end
