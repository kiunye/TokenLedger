defmodule TokenLedgerWeb.ErrorJSON do
  @moduledoc """
  Error JSON render function.
  """

  require Logger

  def template(_assigns) do
    %{
      error: "Internal Server Error",
      message: "An unexpected error has occurred."
    }
    |> Jason.encode!()
  end
end