defmodule TokenLedger.ReorgEvents do
  @moduledoc """
  Persistence boundary for the reorg audit table.

  One row per detected correction, mirroring the observability role
  `reconciliation_runs` plays for the anti-entropy job (§3.2): the record is
  what Phase 3's exit test asserts on, and what the eventual dashboard feed
  renders.
  """

  import Ecto.Query

  alias TokenLedger.ReorgEvents.ReorgEvent
  alias TokenLedger.Repo

  @doc """
  Records a detected fork: fork point, depth, and the number of events just
  orphaned. `resolved_at` stays nil until `mark_resolved/2`.
  """
  @spec record_detection(map()) :: {:ok, ReorgEvent.t()}
  def record_detection(attrs) do
    %ReorgEvent{}
    |> Ecto.Changeset.cast(attrs, [:chain_id, :fork_block, :depth, :events_orphaned])
    |> Ecto.Changeset.validate_required([:chain_id, :fork_block, :depth, :events_orphaned])
    |> Ecto.Changeset.put_change(:detected_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.insert()
  end

  @doc """
  Closes a correction: the listener has re-ingested through the pre-orphan
  tip, so the reapplied count and resolution timestamp are known.
  """
  @spec mark_resolved(ReorgEvent.t(), non_neg_integer()) :: {:ok, ReorgEvent.t()}
  def mark_resolved(%ReorgEvent{} = event, events_reapplied) do
    event
    |> Ecto.Changeset.change(
      events_reapplied: events_reapplied,
      resolved_at: DateTime.utc_now() |> DateTime.truncate(:second)
    )
    |> Repo.update()
  end

  @doc "Newest unresolved correction for a chain, or nil — the watcher's pending-correction lookup."
  @spec pending(integer()) :: ReorgEvent.t() | nil
  def pending(chain_id) do
    ReorgEvent
    |> where([r], r.chain_id == ^chain_id and is_nil(r.resolved_at))
    |> order_by([r], desc: r.detected_at)
    |> limit(1)
    |> Repo.one()
  end

  @doc "All corrections for a chain, newest first. Test and dashboard helper."
  @spec list(integer()) :: [ReorgEvent.t()]
  def list(chain_id) do
    ReorgEvent
    |> where(chain_id: ^chain_id)
    |> order_by([r], desc: r.detected_at)
    |> Repo.all()
  end
end
