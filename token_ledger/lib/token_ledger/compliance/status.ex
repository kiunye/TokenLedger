defmodule TokenLedger.Compliance.Status do
  @moduledoc """
  One compliance action's off-chain-first state (Phase 5). The `status`
  lifecycle is:

  - `pending_revocation` — operator initiated a revocation; on-chain
    `setWhitelisted(addr, false)` not yet confirmed.
  - `pending_reinstate` — operator initiated a re-whitelist; on-chain
    `setWhitelisted(addr, true)` not yet confirmed.
  - `enforced` — the matching confirmed `ComplianceUpdated` has been observed;
    `intent` (`revoke` | `reinstate`) disambiguates which action was enforced.
  - `failed` — submission failed or the tx reverted; retryable, `last_error`
    records the reason.

  This table tracks operator intent + confirmation, NOT the projected
  `accounts.whitelisted` (which remains derived from confirmed events).
  """
  use Ecto.Schema

  import Ecto.Changeset

  @statuses ~w(pending_revocation pending_reinstate enforced failed)
  @intents ~w(revoke reinstate)

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "compliance_statuses" do
    field(:address, :string)
    field(:status, :string)
    field(:intent, :string)
    field(:submitted_tx_hash, :string)
    field(:submitted_at, :utc_datetime)
    field(:initiated_at, :utc_datetime)
    field(:confirmed_at, :utc_datetime)
    field(:last_error, :string)

    timestamps()
  end

  @doc "Valid `status` values."
  def statuses, do: @statuses

  @doc "Valid `intent` values."
  def intents, do: @intents

  @doc "Casts an address to its canonical lowercased form for storage."
  def normalize_address(address) when is_binary(address), do: String.downcase(address)

  def changeset(%__MODULE__{} = status, attrs) do
    status
    |> cast(attrs, [:address, :status, :intent, :submitted_tx_hash, :submitted_at,
      :initiated_at, :confirmed_at, :last_error])
    |> validate_required([:address, :status, :intent, :initiated_at])
    |> update_change(:address, &normalize_address/1)
    |> validate_inclusion(:status, @statuses)
    |> validate_inclusion(:intent, @intents)
    |> unique_constraint(:address)
  end
end
