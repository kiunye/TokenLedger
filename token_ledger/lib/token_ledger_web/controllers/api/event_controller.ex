defmodule TokenLedgerWeb.Api.EventController do
  @moduledoc """
  Stub events endpoint: lists confirmed chain events.
  """

  use TokenLedgerWeb, :controller

  def index(conn, _params) do
    json(conn, %{events: []})
  end
end
