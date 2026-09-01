defmodule TokenLedgerWeb.ErrorHTML do
  @moduledoc """
  Error HTML render function.
  """

  import Phoenix.HTML

  def template(_assigns) do
    """
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Token Ledger API</title>
        <link rel="stylesheet" href="/app.css"/>
      </head>
      <body>
        <div class="container">
          <h1>Something went wrong</h1>
          <p>We apologize for the inconvenience.</p>
        </div>
      </body>
    </html>
    """
  end
end