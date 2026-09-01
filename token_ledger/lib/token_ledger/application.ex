defmodule TokenLedger.Application do
  @moduledoc """
  OTP application entry point.

  Supervision order is intentional (architecture §4.3, PR1):

  `Repo -> Oban -> PubSub -> Telemetry -> Endpoint -> ChainSupervisor`.

  `Repo` and `Oban` must be up before anything touches the database;
  `PubSub` must be alive before `Endpoint` subscribes; `Endpoint`
  must be ready before `ChainSupervisor` starts emitting PubSub
  broadcasts. `start_chain_supervisor: false` (test lifecycle control)
  suppresses only the final child, not the web stack.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        TokenLedger.Repo,
        {Oban, Application.fetch_env!(:token_ledger, Oban)},
        {Phoenix.PubSub, name: TokenLedger.PubSub},
        TokenLedgerWeb.Telemetry,
        TokenLedgerWeb.Endpoint
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
