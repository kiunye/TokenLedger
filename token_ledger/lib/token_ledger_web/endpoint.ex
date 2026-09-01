defmodule TokenLedgerWeb.Endpoint do
  @moduledoc """
  Phoenix endpoint for TokenLedger dashboard and JSON API.

  Plug pipeline: static assets, request telemetry, parsers, session,
  then the router. LiveView websocket at `/live` reuses the same session
  store. Bandit is the HTTP adapter.
  """

  use Phoenix.Endpoint, otp_app: :token_ledger

  @session_options [
    store: :cookie,
    key: "_token_ledger_key",
    signing_salt: "change_me_signing_salt",
    same_site: "Lax"
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: false

  # Serves files from `priv/static` at `/` with no code reloading.
  plug Plug.Static,
    at: "/",
    from: :token_ledger,
    gzip: false,
    only: TokenLedgerWeb.static_paths()

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  plug TokenLedgerWeb.Router
end
