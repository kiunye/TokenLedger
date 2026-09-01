defmodule TokenLedgerWeb.Api.EventController do
  use TokenLedgerWeb, :controller

  action_fallback TokenLedgerWeb.FallbackController

  def index(conn, _params) do
    events = [] # TODO: call TokenLedger.Events.get_recent_events() or similar
    json(conn, events)
  end
end