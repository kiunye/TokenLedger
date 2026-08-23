defmodule TokenLedger.ChainEvents.Event do
  @moduledoc """
  One ingested on-chain event: a row of the append-only event log
  (`chain_events`, architecture §3.2).

  `payload` holds decoded semantic fields plus a nested `raw` copy of the
  log's topics/data (design decision 5). `confirmed`/`orphaned` ship false and
  are flipped by later phases; this phase only ever appends.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @derive {Jason.Encoder, except: [:__meta__]}

  schema "chain_events" do
    field(:chain_id, :integer)
    field(:block_number, :integer)
    field(:block_hash, :string)
    field(:log_index, :integer)
    field(:event_type, :string)
    field(:payload, :map)
    field(:confirmed, :boolean, default: false)
    field(:orphaned, :boolean, default: false)

    timestamps(updated_at: false, type: :utc_datetime)
  end

  @doc """
  Builds the insert-ready row map consumed by `TokenLedger.ChainEvents.persist_events/2`.
  Kept next to the schema so the required keys have exactly one definition.

  Accepts string-keyed payload maps (as produced by the decoder); Ecto's
  `:map` type dumps them to jsonb verbatim.
  """
  @spec row(map(), DateTime.t()) :: %{
          chain_id: integer(),
          block_number: pos_integer(),
          block_hash: String.t(),
          log_index: non_neg_integer(),
          event_type: String.t(),
          payload: map(),
          confirmed: boolean(),
          orphaned: boolean(),
          inserted_at: DateTime.t()
        }
  def row(attrs, now) do
    %{
      chain_id: Map.fetch!(attrs, :chain_id),
      block_number: Map.fetch!(attrs, :block_number),
      block_hash: Map.fetch!(attrs, :block_hash),
      log_index: Map.fetch!(attrs, :log_index),
      event_type: Map.fetch!(attrs, :event_type),
      payload: Map.fetch!(attrs, :payload),
      confirmed: false,
      orphaned: false,
      inserted_at: now
    }
  end
end
