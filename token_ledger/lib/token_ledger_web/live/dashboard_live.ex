defmodule TokenLedgerWeb.DashboardLive do
  @moduledoc """
  Dashboard LiveView: confirmed balances and chain head overview.

  Shows the chain's confirmed state, including:
  - Chain head (highest persisted block)
  - Confirmed head (highest confirmed block)
  - Lag between chain and confirmed state
  - Recent confirmed events
  """

  use TokenLedgerWeb, :live_view

  alias TokenLedger.ChainConfig
  alias TokenLedger.ChainEvents

  @impl true
  def mount(_params, _session, socket) do
    chain_id = ChainConfig.chain_id()
    summary = ChainEvents.confirmed_summary(chain_id)
    events = ChainEvents.list_confirmed_events(chain_id, limit: 10)

    socket =
      socket
      |> assign(:chain_id, chain_id)
      |> assign(:chain_head, summary.chain_head || 0)
      |> assign(:confirmed_head, summary.confirmed_head || 0)
      |> assign(:lag, (summary.chain_head || 0) - (summary.confirmed_head || 0))
      |> assign(:events, events)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold mb-6">Token Ledger Dashboard</h1>

      <div class="grid grid-cols-2 gap-4 mb-8">
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
      </div>

      <div class="bg-white shadow rounded-lg p-4 mb-8">
        <div class="text-sm text-gray-500">Sync Status</div>
        <div class="text-lg font-semibold" id="sync-status">
          <%= if @lag == 0 do %>
            <span class="text-green-600">Synced</span>
          <% else %>
            <span class="text-yellow-600">Syncing (lag: <%= @lag %> blocks)</span>
          <% end %>
        </div>
      </div>

      <h2 class="text-xl font-bold mb-4">Recent Confirmed Events</h2>
      <div class="bg-white shadow rounded-lg overflow-hidden">
        <%= if @events == [] do %>
          <div class="p-4 text-gray-500">No confirmed events yet</div>
        <% else %>
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Block</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Log</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Type</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Details</th>
              </tr>
            </thead>
            <tbody id="events-table" class="bg-white divide-y divide-gray-200">
              <%= for event <- @events do %>
                <tr>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900" id={"block-#{event.block_number}-#{event.log_index}"}>
                    <%= event.block_number %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= event.log_index %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <span class="px-2 inline-flex text-xs leading-5 font-semibold rounded-full bg-blue-100 text-blue-800">
                      <%= event.event_type %>
                    </span>
                  </td>
                  <td class="px-6 py-4 text-sm text-gray-900">
                    <%= format_payload(event) %>
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

  defp format_payload(event) do
    case event.event_type do
      "transfer" ->
        from = Map.get(event.payload, "from", "unknown") |> String.slice(0, 10) |> Kernel.<>("...")
        to = Map.get(event.payload, "to", "unknown") |> String.slice(0, 10) |> Kernel.<>("...")
        amount = Map.get(event.payload, "amount", "0")
        "#{from} → #{to}: #{amount}"

      "compliance_updated" ->
        account = Map.get(event.payload, "account", "unknown") |> String.slice(0, 10) |> Kernel.<>("...")
        status = if Map.get(event.payload, "whitelisted"), do: "whitelisted", else: "revoked"
        "#{account}: #{status}"

      _ ->
        Jason.encode!(event.payload)
    end
  end
end
