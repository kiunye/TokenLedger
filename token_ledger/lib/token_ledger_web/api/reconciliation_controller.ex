defmodule TokenLedgerWeb.Api.ReconciliationController do
  use TokenLedgerWeb, :controller

  action_fallback TokenLedgerWeb.FallbackController

  def status(conn, _params) do
    status = %{
      last_processed_block: 0,
      pending_gaps: [],
      status: :idle
    } # TODO: call TokenLedger.Reconciliation.get_status()
    json(conn, status)
  end
end