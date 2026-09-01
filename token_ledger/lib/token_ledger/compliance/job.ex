defmodule TokenLedger.Compliance.Job do
  @moduledoc """
  Oban worker that drives the compliance workflow (Phase 5).

  Runs on a short cron (every minute in dev) and:
  1. Confirms any already-confirmed pending states to enforced
  2. Submits pending transactions via the configured Submitter
  3. Polls receipts for submitted transactions and marks reverted ones failed

  Crash-safe: uses idempotent updates and database state tracks intent/tx_hash.
  Per-row errors are isolated so one malformed address does not abort the batch.
  """

  use Oban.Worker, queue: :compliance

  alias TokenLedger.Compliance.Confirmer
  alias TokenLedger.Compliance.Submitter
  alias TokenLedger.Repo
  alias TokenLedger.RPC.Client
  import Ecto.Query
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{} = _job) do
    chain_id = TokenLedger.ChainConfig.chain_id()

    Confirmer.confirm(chain_id)
    process_pending_rows()
    poll_submitted_rows()

    :ok
  end

  defp process_pending_rows do
    from(s in TokenLedger.Compliance.Status,
      where: s.status in ["pending_revocation", "pending_reinstate"] and is_nil(s.submitted_at)
    )
    |> Repo.all()
    |> Enum.each(&safe_process_row/1)
  end

  defp safe_process_row(row) do
    process_row(row)
  rescue
    exception ->
      Logger.warning("Compliance Job row #{row.id} crashed: #{Exception.message(exception)}")

      query = from(s in TokenLedger.Compliance.Status, where: s.id == ^row.id)
      Repo.update_all(query, set: [status: "failed", last_error: Exception.message(exception)])
  end

  defp process_row(%{address: address, status: status, id: id}) do
    case submit_for_status(address, status) do
      {:ok, tx_hash} ->
        query = from(s in TokenLedger.Compliance.Status, where: s.id == ^id)
        Repo.update_all(query, set: [submitted_at: DateTime.utc_now(), submitted_tx_hash: tx_hash])

      {:error, :invalid_address} ->
        query = from(s in TokenLedger.Compliance.Status, where: s.id == ^id)
        Repo.update_all(query, set: [status: "failed", last_error: "invalid address"])

      {:error, reason} ->
        query = from(s in TokenLedger.Compliance.Status, where: s.id == ^id)
        Repo.update_all(query, set: [last_error: inspect(reason)])
    end

    :ok
  end

  defp poll_submitted_rows do
    from(s in TokenLedger.Compliance.Status,
      where: s.status in ["pending_revocation", "pending_reinstate"] and not is_nil(s.submitted_tx_hash)
    )
    |> Repo.all()
    |> Enum.each(&poll_receipt/1)
  end

  defp poll_receipt(%{id: id, submitted_tx_hash: tx_hash}) do
    case Client.get_transaction_receipt(tx_hash) do
      {:ok, %{"status" => "0x0"}} ->
        query = from(s in TokenLedger.Compliance.Status, where: s.id == ^id)
        Repo.update_all(query, set: [status: "failed", last_error: "transaction reverted"])

      {:ok, %{"status" => "0x1"}} ->
        :ok

      {:ok, nil} ->
        :ok

      {:error, reason} ->
        Logger.warning("Receipt poll failed for #{tx_hash}: #{inspect(reason)}")
        :ok
    end
  rescue
    exception ->
      Logger.warning("Receipt poll crashed for #{tx_hash}: #{Exception.message(exception)}")
      :ok
  end

  defp submit_for_status(address, "pending_revocation"), do: Submitter.submit_revocation(address)
  defp submit_for_status(address, "pending_reinstate"), do: Submitter.submit_reinstate(address)
  defp submit_for_status(_, _), do: {:error, :invalid_state}
end
