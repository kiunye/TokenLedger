defmodule TokenLedger.Compliance.Confirmer do
  @moduledoc """
  Confirmed compliance event detection and state finalization (Phase 5).

  Observes on-chain `ComplianceUpdated` events for addresses in a `pending_*`
  state and flips them to `enforced` when the matching confirmed event is
  observed. Uses the same confirmation mechanism as the reorg watcher (Phase 3)
  to ensure we only act on finalized state.
  """

  import Ecto.Query
  alias TokenLedger.ChainEvents.Event
  alias TokenLedger.Compliance.Status
  alias TokenLedger.Repo

  @doc """
  Flips `pending_*` compliance statuses to `enforced` when a matching
  confirmed `ComplianceUpdated` event exists for that address.
  """
  @spec confirm(integer()) :: :ok
  def confirm(chain_id) do
    addresses =
      Event
      |> where([e], e.chain_id == ^chain_id and e.event_type == "compliance_updated")
      |> where([e], e.confirmed and not e.orphaned)
      |> select([e], e.payload["account"])
      |> distinct([e], e.payload["account"])
      |> Repo.all()

    Enum.each(addresses, fn address -> process_address(address, chain_id) end)
    :ok
  end

  defp process_address(address, chain_id) do
    query =
      from(s in Status,
        where: s.address == ^address and s.status in ["pending_revocation", "pending_reinstate"]
      )

    Repo.all(query)
    |> Enum.each(fn status -> maybe_enforce(status, chain_id) end)
  end

  defp maybe_enforce(%{id: id, status: status, address: address}, chain_id) do
    expected = status_to_whitelist(status)

    if has_compliance_event?(address, expected, chain_id) do
      query = from(s in Status, where: s.id == ^id)
      Repo.update_all(query, set: [status: "enforced", confirmed_at: DateTime.utc_now()])
    end

    :ok
  end

  defp status_to_whitelist("pending_revocation"), do: false
  defp status_to_whitelist("pending_reinstate"), do: true

  defp has_compliance_event?(address, whitelisted, chain_id) do
    Event
    |> where([e], e.chain_id == ^chain_id and e.event_type == "compliance_updated")
    |> where([e], e.confirmed and not e.orphaned)
    |> where([e], e.payload["account"] == ^address and e.payload["whitelisted"] == ^whitelisted)
    |> Repo.exists?()
  end
end
