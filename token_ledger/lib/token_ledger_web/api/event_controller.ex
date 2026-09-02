defmodule TokenLedgerWeb.Api.EventController do
  @moduledoc """
  Returns confirmed, non-orphaned events for the configured chain.

  All events returned by this controller are guaranteed to be finalized:
  confirmed by the chain's finality mechanism and not rolled back by a reorg.
  """

  use TokenLedgerWeb, :controller
  import Phoenix.Controller, only: [json: 2]

  alias TokenLedger.ChainConfig
  alias TokenLedger.ChainEvents

  def index(conn, params) do
    limit = parse_limit(params["limit"])
    chain_id = ChainConfig.chain_id()

    events = ChainEvents.list_confirmed_events(chain_id, limit: limit)

    json(conn, Enum.map(events, &event_to_json/1))
  end

  defp parse_limit(nil), do: 20
  defp parse_limit(limit_str) when is_binary(limit_str) do
    case Integer.parse(limit_str) do
      {n, _} when n > 0 and n <= 100 -> n
      _ -> 20
    end
  end
  defp parse_limit(_), do: 20

  defp event_to_json(event) do
    %{
      "block_number" => event.block_number,
      "log_index" => event.log_index,
      "event_type" => event.event_type,
      "payload" => event.payload,
      "confirmed" => event.confirmed
    }
  end
end