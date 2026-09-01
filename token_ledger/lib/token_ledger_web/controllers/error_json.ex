defmodule TokenLedgerWeb.ErrorJSON do
  @moduledoc """
  Renders JSON error payloads for the Phoenix endpoint.
  """

  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
