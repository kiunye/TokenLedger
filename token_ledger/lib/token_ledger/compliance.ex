defmodule TokenLedger.Compliance do
  @moduledoc """
  Off-chain-first compliance workflow (Phase 5).

  Operator intent is recorded as a `pending_*` row before any on-chain
  submission. The `TokenLedger.Compliance.Job` later submits via the
  configured `Submitter` and the `Confirmer` flips to `enforced` once a
  confirmed `ComplianceUpdated` event is observed. This module is the single
  entry point for initiating and querying compliance state — the projected
  `accounts.whitelisted` remains the derived source of truth.
  """

  alias TokenLedger.Compliance.Status
  alias TokenLedger.Repo
  import Ecto.Query

  @doc """
  Initiates revocation for `address`: creates or updates the
  `compliance_statuses` row to `pending_revocation` with `intent: "revoke"`.
  Idempotent — re-calling on an already-pending revocation is a no-op;
  calling on a different intent overwrites to the new intent.
  """
  @spec initiate_revocation(String.t()) :: {:ok, Status.t()} | {:error, Ecto.Changeset.t()}
  def initiate_revocation(address) when is_binary(address) do
    upsert_status(address, "pending_revocation", "revoke")
  end

  @doc """
  Initiates re-whitelisting for `address`: creates or updates the row to
  `pending_reinstate` with `intent: "reinstate"`.
  """
  @spec initiate_reinstate(String.t()) :: {:ok, Status.t()} | {:error, Ecto.Changeset.t()}
  def initiate_reinstate(address) when is_binary(address) do
    upsert_status(address, "pending_reinstate", "reinstate")
  end

  @doc "Fetches the compliance status for `address`, or `nil` when none exists."
  @spec get_status(String.t()) :: Status.t() | nil
  def get_status(address) when is_binary(address) do
    Repo.get_by(Status, address: String.downcase(address))
  end

  @doc "Lists all statuses, ordered by `initiated_at`."
  @spec list_statuses() :: [Status.t()]
  def list_statuses do
    Status |> order_by([s], asc: s.initiated_at) |> Repo.all()
  end

  defp upsert_status(address, status, intent) do
    normalized = String.downcase(address)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(Status, address: normalized) do
      nil ->
        %Status{}
        |> Status.changeset(%{
          address: normalized,
          status: status,
          intent: intent,
          initiated_at: now
        })
        |> Repo.insert()

      existing ->
        existing
        |> Status.changeset(%{
          status: status,
          intent: intent,
          initiated_at: now,
          submitted_at: nil,
          submitted_tx_hash: nil,
          confirmed_at: nil,
          last_error: nil
        })
        |> Repo.update()
    end
  end
end
