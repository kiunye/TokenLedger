defmodule TokenLedgerWeb.ErrorHTML do
  @moduledoc """
  Renders HTML error pages for the Phoenix endpoint.
  """

  use TokenLedgerWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
