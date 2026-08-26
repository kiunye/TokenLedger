defmodule TokenLedger.Reconciliation do
  @moduledoc """
  Audit writes and reads for `reconciliation_runs` (design decision 7).

  Each scheduled pass records its start heights, then is closed with the gap
  backfilled and whether a reorg was observed inside the run window. A run is a
  queryable fact: "an induced gap is detected and backfilled" is asserted
  against this table by the Phase 4 integration test.
  """
  import Ecto.Query

  alias TokenLedger.Reconciliation.Run
  alias TokenLedger.ReorgEvents.ReorgEvent
  alias TokenLedger.Repo

  @spec start_run(integer(), integer(), integer()) :: Run.t()
  def start_run(chain_id, chain_height, indexed_height) do
    %Run{}
    |> Ecto.Changeset.change(%{
      chain_id: chain_id,
      started_at: DateTime.utc_now() |> DateTime.truncate(:second),
      chain_height_at_start: chain_height,
      indexed_height_at_start: indexed_height
    })
    |> Repo.insert!()
  end

  @spec finish_run(Run.t(), non_neg_integer(), boolean()) :: Run.t()
  def finish_run(run, gap_blocks_backfilled, reorg_detected) do
    run
    |> Ecto.Changeset.change(%{
      completed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      gap_blocks_backfilled: gap_blocks_backfilled,
      reorg_detected: reorg_detected
    })
    |> Repo.update!()
  end

  @spec reorg_in_window?(integer(), DateTime.t(), DateTime.t()) :: boolean()
  def reorg_in_window?(chain_id, started_at, completed_at) do
    ReorgEvent
    |> where(
      [r],
      r.chain_id == ^chain_id and r.detected_at >= ^started_at and r.detected_at <= ^completed_at
    )
    |> Repo.exists?()
  end
end
