defmodule TokenLedgerWeb.ReconciliationLive do
  @moduledoc """
  Reconciliation LiveView: lag, gaps, and recent runs.
  """

  use TokenLedgerWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>Reconciliation</div>
    """
  end
end
