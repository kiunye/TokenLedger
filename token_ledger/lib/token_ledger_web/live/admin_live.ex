defmodule TokenLedgerWeb.AdminLive do
  @moduledoc """
  Admin LiveView: compliance workflow management.

  Shows compliance statuses for all accounts, including:
  - Current whitelist status
  - Pending revocations
  - On-chain enforcement status
  """

  use TokenLedgerWeb, :live_view

  alias TokenLedger.Compliance

  @impl true
  def mount(_params, _session, socket) do
    statuses = Compliance.list_statuses()

    socket =
      socket
      |> assign(:statuses, statuses)

    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 py-8">
      <h1 class="text-2xl font-bold mb-6">Compliance Administration</h1>

      <div class="bg-white shadow rounded-lg overflow-hidden">
        <%= if @statuses == [] do %>
          <div class="p-4 text-gray-500">No compliance statuses yet</div>
        <% else %>
          <table class="min-w-full divide-y divide-gray-200">
            <thead class="bg-gray-50">
              <tr>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Address</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Intent</th>
                <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Initiated At</th>
              </tr>
            </thead>
            <tbody id="statuses-table" class="bg-white divide-y divide-gray-200">
              <%= for status <- @statuses do %>
                <tr id={"status-#{status.id}"}>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900 font-mono">
                    <%= status.address |> String.slice(0, 10) <> "..." %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <span class={"px-2 inline-flex text-xs leading-5 font-semibold rounded-full #{status_class(status.status)}"}>
                      <%= status.status %>
                    </span>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                    <%= status.intent %>
                  </td>
                  <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                    <%= status.initiated_at |> DateTime.to_string() |> String.slice(0, 19) %>
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

  defp status_class("pending_revocation"), do: "bg-yellow-100 text-yellow-800"
  defp status_class("pending_reinstate"), do: "bg-blue-100 text-blue-800"
  defp status_class("enforced"), do: "bg-green-100 text-green-800"
  defp status_class("failed"), do: "bg-red-100 text-red-800"
  defp status_class(_), do: "bg-gray-100 text-gray-800"
end
