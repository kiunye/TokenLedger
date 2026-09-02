defmodule TokenLedgerWeb do
  @moduledoc """
  Web entry point: helpers for controllers, LiveViews, and verified routes.
  Mirrors `mix phx.new` conventions without asset tooling. Keeps verified
  routes and static path knowledge in one place.
  """

  def static_paths, do: ~w(app.css favicon.ico robots.txt)

  def __using__(which) when which in [:controller, :live_view, :live_component, :html] do
    apply(__MODULE__, which, [])
  end

  def controller do
    quote bind_quoted: [endpoint: __MODULE__.Endpoint] do
      use Phoenix.Controller, formats: [:html, :json]

      import Plug.Conn
      import Phoenix.Controller, only: [action_fallback: 1, json: 2]

      unquote(verified_routes())
    end
  end

  def live_view do
    quote bind_quoted: [endpoint: __MODULE__.Endpoint] do
      use Phoenix.LiveView

      unquote(html_helpers())
    end
  end

  def live_component do
    quote bind_quoted: [endpoint: __MODULE__.Endpoint] do
      use Phoenix.LiveComponent

      unquote(html_helpers())
    end
  end

  def html do
    quote do
      use Phoenix.Component

      import Phoenix.Controller,
        only: [get_csrf_token: 0, view_module: 1, view_template: 1]

      unquote(html_helpers())
    end
  end

  defp html_helpers do
    quote do
      import Phoenix.HTML
      import Phoenix.HTML.Form
      import Phoenix.HTML.Link

      use Phoenix.VerifiedRoutes,
        endpoint: TokenLedgerWeb.Endpoint,
        router: TokenLedgerWeb.Router,
        statics: TokenLedgerWeb.static_paths()
    end
  end

  defp verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: TokenLedgerWeb.Endpoint,
        router: TokenLedgerWeb.Router,
        statics: TokenLedgerWeb.static_paths()
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