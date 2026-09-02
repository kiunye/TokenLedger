defmodule TokenLedgerWeb.Api.ReconciliationController do
  @moduledoc """
  Returns the reconciliation status for the configured chain.

  Shows the chain head, confirmed head, and lag between them, plus the
  count of reconciliation runs recorded in the database.
  """

  use TokenLedgerWeb, :controller

  alias TokenLedger.ChainConfig
  alias TokenLedger.ChainEvents
  alias TokenLedger.Reconciliation
  alias TokenLedger.Reconciliation.Run
  alias TokenLedger.Repo
  import Ecto.Query

  def status(conn, _params) do
    chain_id = ChainConfig.chain_id()

    summary = ChainEvents.confirmed_summary(chain_id)
    chain_head = summary.chain_head || 0
    confirmed_head = summary.confirmed_head || 0
    lag = chain_head - confirmed_head

    last_run =
      Run
      |> where(chain_id: ^chain_id)
      |> order_by(desc: :started_at)
      |> limit(1)
      |> Repo.one()
      |> case do
        nil -> nil
        run ->
          %{
            "id" => run.id,
            "started_at" => run.started_at,
            "completed_at" => run.completed_at,
            "gap_blocks_backfilled" => run.gap_blocks_backfilled,
            "reorg_detected" => run.reorg_detected
          }
      end

    json(conn, %{
      "chain_id" => chain_id,
      "chain_head" => chain_head,
      "confirmed_head" => confirmed_head,
      "lag" => lag,
      "status" => if(lag == 0, do: "synced", else: "syncing"),
      "last_run" => last_run
    })
  end
end