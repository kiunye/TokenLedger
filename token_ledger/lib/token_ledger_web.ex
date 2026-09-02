defmodule TokenLedgerWeb do
  @moduledoc """
  Web entry point: helpers for controllers, LiveViews, and verified routes.
  Mirrors `mix phx.new` conventions without asset tooling. Keeps verified
  routes and static path knowledge in one place.
  """

  def static_paths, do: ~w(app.css favicon.ico robots.txt)

  defmacro __using__(which) do
    case which do
      :controller ->
        quote do
          use Phoenix.Controller, formats: [:html, :json]
          import Plug.Conn
          use Phoenix.VerifiedRoutes,
            endpoint: TokenLedgerWeb.Endpoint,
            router: TokenLedgerWeb.Router,
            statics: TokenLedgerWeb.static_paths()
        end

      :live_view ->
        quote do
          use Phoenix.LiveView
          use Phoenix.VerifiedRoutes,
            endpoint: TokenLedgerWeb.Endpoint,
            router: TokenLedgerWeb.Router,
            statics: TokenLedgerWeb.static_paths()
          import Phoenix.HTML
          import Phoenix.HTML.Form
          import Phoenix.HTML.Link
        end

      :live_component ->
        quote do
          use Phoenix.LiveComponent
          use Phoenix.VerifiedRoutes,
            endpoint: TokenLedgerWeb.Endpoint,
            router: TokenLedgerWeb.Router,
            statics: TokenLedgerWeb.static_paths()
          import Phoenix.HTML
          import Phoenix.HTML.Form
          import Phoenix.HTML.Link
        end

      :html ->
        quote do
          use Phoenix.Component
          import Phoenix.Controller,
            only: [get_csrf_token: 0, view_module: 1, view_template: 1]
          use Phoenix.VerifiedRoutes,
            endpoint: TokenLedgerWeb.Endpoint,
            router: TokenLedgerWeb.Router,
            statics: TokenLedgerWeb.static_paths()
          import Phoenix.HTML
          import Phoenix.HTML.Form
          import Phoenix.HTML.Link
        end

      :router ->
        quote do
          use Phoenix.Router, helpers: false
          import Plug.Conn
          import Phoenix.Controller
          import Phoenix.LiveView.Router
        end

      :channel ->
        quote do
          use Phoenix.Channel
        end

      _ ->
        raise ArgumentError, "unknown use target: #{inspect(which)}"
    end
  end

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
    end
  end
end
