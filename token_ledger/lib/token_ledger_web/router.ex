defmodule TokenLedgerWeb.Router do
  @moduledoc """
  Router for TokenLedger: browser LiveViews and JSON API.

  Browser scope hosts the dashboard, account, admin, and reconciliation
  LiveViews. API scope exposes balance, events, reconciliation status,
  and the transfer simulate endpoint.
  """

  use TokenLedgerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_secure_browser_headers
    plug :protect_from_forgery
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug TokenLedgerWeb.Plugs.RateLimiter
  end

  scope "/", TokenLedgerWeb do
    pipe_through :browser

    live "/", DashboardLive, :index
    live "/account/:address", AccountLive, :show
    live "/admin", AdminLive, :index
    live "/reconciliation", ReconciliationLive, :index
  end

  scope "/api", TokenLedgerWeb.Api do
    pipe_through :api

    get "/balance/:address", BalanceController, :show
    get "/events", EventController, :index
    get "/reconciliation/status", ReconciliationController, :status
    post "/transfers/simulate", TransferController, :simulate
  end
end
