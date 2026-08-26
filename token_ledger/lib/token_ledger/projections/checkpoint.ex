defmodule TokenLedger.Projections.Checkpoint do
  @moduledoc """
  Durable projection cursor (design decision 2). `last_block_number` /
  `last_log_index` together form the `(block_number, log_index)` identity the
  projection resumes from, keyed per chain. A missing row means "start from the
  beginning", represented in code as `{block_number: -1, log_index: -1}`.
  """
  use Ecto.Schema

  @primary_key false
  schema "projection_checkpoints" do
    field(:chain_id, :integer, primary_key: true)
    field(:last_block_number, :integer, default: -1)
    field(:last_log_index, :integer, default: -1)

    timestamps(type: :utc_datetime, updated_at: true, inserted_at: false)
  end
end
