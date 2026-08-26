defmodule TokenLedger.Application do
  @moduledoc """
  OTP application entry point.

  Starts Ecto and Oban, then — unless `start_chain_supervisor: false` (test
  lifecycle control) — the chain supervision tree from architecture §4.3.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        TokenLedger.Repo,
        {Oban, Application.fetch_env!(:token_ledger, Oban)}
      ]
      |> Enum.concat(chain_children())

    opts = [strategy: :one_for_one, name: TokenLedger.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp chain_children do
    if Application.get_env(:token_ledger, :start_chain_supervisor, true) do
      [TokenLedger.ChainSupervisor]
    else
      []
    end
  end
end
