defmodule TokenLedgerWeb.ReconciliationLive do
  @moduledoc """
  Reconciliation LiveView: lag, gaps, and recent runs.

  Shows the reconciliation status including:
  - Chain head vs confirmed head (lag)
  - Recent reconciliation runs
  - Whether reorgs were detected during runs
  """

  use TokenLedgerWeb, :live_view

  alias TokenLedger.ChainConfig
  alias TokenLedger.ChainEvents
  alias TokenLedger.Reconciliation.Run
  alias TokenLedger.Repo

  @impl true
  def mount(_params, _session, socket) do
    chain_id = ChainConfig.chain_id()
    summary = ChainEvents.confirmed_summary(chain_id)
    runs = Repo.all(Run |> where(chain_id: ^chain_id) |> order_by(desc: :started_at) |> limit(10))

    socket =
      socket
      |> assign(:chain_id, chain_id)
      |> assign(:chain_head, summary.chain_head || 0)
      |> assign(:confirmed_head, summary.confirmed_head || 0)
      |> assign(:lag, (summary.chain_head || 0) - (summary.confirmed_head || 0))
      |> assign(:runs, runs)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold mb-6">Reconciliation Status</h1>

      <div class="grid grid-cols-3 gap-4 mb-8">
        <div class="bg-white shadow rounded-lg p-4">
          <div class="text-sm text-gray-500">Chain Head</div>
          <div class="text-3xl font-bold" id="chain-head">
            <%= @chain_head %>
          </div>
        </div>

        <div class="bg-white shadow rounded-lg p-4">
          <div class="text-sm text-gray-500">Confirmed Head</div>
          <div class="text-3xl font-bold" id="confirmed-head">
            <%= @confirmed_head %>
          </div>
        </div>

        <div class="bg-white shadow rounded-lg p-4">
          <div class="text-sm text-gray-500">Lag</div>
          <div class="text-3xl font-bold" id="lag">
            <%= @lag %>
          </div>
        </div>
      </div>

      <h2 class="text-xl font-bold mb-4">Recent Reconciliation Runs</h2>
      <div class="bg-white shadow rounded-lg overflow-hidden">
        <%= if @runs == [] do %>
          <div class="p-4 text-gray-500">No reconciliation runs yet</div>
        <% else %>
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Started</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Completed</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Chain Height</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Indexed Height</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Gap Backfilled</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Reorg Detected</th>
              </tr>
            </thead>
            <tbody id="runs-table" class="bg-white divide-y divide-gray-200">
              <%= for run <- @runs do %>
                <tr id={"run-#{run.id}"}>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= run.started_at |> DateTime.to_string() |> String.slice(0, 19) %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= if run.completed_at do %>
                      <%= run.completed_at |> DateTime.to_string() |> String.slice(0, 19) %>
                    <% else %>
                      <span class="text-yellow-600">Running</span>
                    <% end %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= run.chain_height_at_start %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= run.indexed_height_at_start %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= run.gap_blocks_backfilled %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{reorg_class(run.reorg_detected)}"}>
                      <%= if run.reorg_detected, do: "Yes", else: "No" %>
                    </span>
                  </td>
                </tr>
              <% end %>
            </tbody>
          </table>
        <% end %>
      </div>
    </div>
    """
  end

  defp reorg_class(true), do: "bg-red-100 text-red-800"
  defp reorg_class(false), do: "bg-green-100 text-green-800"
end
