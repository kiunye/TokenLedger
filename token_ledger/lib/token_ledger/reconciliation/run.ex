defmodule TokenLedger.Reconciliation.Run do
  @moduledoc """
  One scheduled reconciliation pass (design decision 7). Records chain and
  indexed heights at start, the gap backfilled, and whether a reorg was observed
  within the run window. `completed_at` is null until the run finishes.
  """
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "reconciliation_runs" do
    field(:chain_id, :integer)
    field(:started_at, :utc_datetime)
    field(:completed_at, :utc_datetime)
    field(:chain_height_at_start, :integer)
    field(:indexed_height_at_start, :integer)
    field(:gap_blocks_backfilled, :integer, default: 0)
    field(:reorg_detected, :boolean, default: false)

    timestamps(updated_at: false, type: :utc_datetime)
  end
end
