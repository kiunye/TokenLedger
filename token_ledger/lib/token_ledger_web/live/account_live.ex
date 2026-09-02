defmodule TokenLedgerWeb.AccountLive do
  @moduledoc """
  Account LiveView: per-address confirmed balance and event history.

  Shows the projected (confirmed-only) balance and the confirmed
  transfer events for a specific address.
  """

  use TokenLedgerWeb, :live_view

  alias TokenLedger.ChainConfig
  alias TokenLedger.ChainEvents
  alias TokenLedger.Projections.Balance
  alias TokenLedger.Repo

  @impl true
  def mount(%{"address" => address}, _session, socket) do
    chain_id = ChainConfig.chain_id()
    balance = Repo.get(Balance, address)
    events = ChainEvents.list_confirmed_events_for_address(chain_id, address, limit: 20)

    socket =
      socket
      |> assign(:address, address)
      |> assign(:balance, balance)
      |> assign(:events, events)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold mb-6">Account</h1>

      <div class="bg-white shadow rounded-lg p-4 mb-8">
        <div class="text-sm text-gray-500">Address</div>
        <div class="text-lg font-mono" id="address">
          <%= @address %>
        </div>
      </div>

      <div class="bg-white shadow rounded-lg p-4 mb-8">
        <div class="text-sm text-gray-500">Confirmed Balance</div>
        <div class="text-3xl font-bold" id="balance">
          <%= if @balance do %>
            <%= Decimal.to_string(@balance.amount) %>
          <% else %>
            0
          <% end %>
        </div>
        <%= if @balance do %>
          <div class="text-sm text-gray-500">
            As of block: <%= @balance.as_of_block %>
          </div>
        <% end %>
      </div>

      <h2 class="text-xl font-bold mb-4">Confirmed Transfer Events</h2>
      <div class="bg-white shadow rounded-lg overflow-hidden">
        <%= if @events == [] do %>
          <div class="p-4 text-gray-500">No confirmed transfer events yet</div>
        <% else %>
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Block</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">From</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">To</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Amount</th>
              </tr>
            </thead>
            <tbody id="events-table" class="bg-white divide-y divide-gray-200">
              <%= for event <- @events do %>
                <tr>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900" id={"event-#{event.block_number}-#{event.log_index}"}>
                    <%= event.block_number %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 font-mono">
                    <%= event.payload["from"] |> String.slice(0, 10) <> "..." %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 font-mono">
                    <%= event.payload["to"] |> String.slice(0, 10) <> "..." %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= event.payload["amount"] %>
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
end
