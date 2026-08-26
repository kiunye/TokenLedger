defmodule TokenLedger.ReorgEvents.ReorgEvent do
  @moduledoc """
  One detected reorg correction (audit table, design decision 5).

  `resolved_at` is NULL until the listener has re-ingested through the
  pre-orphan tip; it stays NULL permanently for over-depth incidents, which
  are escalated rather than auto-rolled-back.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Jason.Encoder, except: [:__meta__]}

  schema "reorg_events" do
    field(:chain_id, :integer)
    field(:fork_block, :integer)
    field(:depth, :integer)
    field(:events_orphaned, :integer, default: 0)
    field(:events_reapplied, :integer, default: 0)
    field(:detected_at, :utc_datetime)
    field(:resolved_at, :utc_datetime)

    timestamps(updated_at: false, type: :utc_datetime)
  end
end
