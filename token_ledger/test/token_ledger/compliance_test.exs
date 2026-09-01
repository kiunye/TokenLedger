defmodule TokenLedger.ComplianceTest do
  # Phase 5: off-chain-first compliance workflow. Serialized against the
  # integration suite because it touches the shared test database.
  use ExUnit.Case, async: false

  alias TokenLedger.ChainEvents
  alias TokenLedger.ChainEvents.Event
  alias TokenLedger.Compliance.Confirmer
  alias TokenLedger.Compliance.NodeSubmitter
  alias TokenLedger.Compliance.Status
  alias TokenLedger.Compliance.Submitter
  alias TokenLedger.Repo

  import Ecto.Query

  @chain_id 95_001

  setup do
    Repo.delete_all(Status)
    Repo.delete_all(from(e in Event, where: e.chain_id == ^@chain_id))
    :ok
  end

  defp persist_status(attrs) do
    %Status{}
    |> Status.changeset(attrs)
    |> Repo.insert!()
  end

  defp compliance_event(account, whitelisted, block, log_index) do
    %{
      chain_id: @chain_id,
      block_number: block,
      block_hash: "0xh#{block}",
      log_index: log_index,
      event_type: "compliance_updated",
      payload: %{
        "account" => account,
        "whitelisted" => whitelisted,
        "raw" => %{"topics" => [], "data" => "0x"}
      }
    }
  end

  describe "Status changeset" do
    test "normalizes addresses to lowercase" do
      cs = Status.changeset(%Status{}, %{
        address: "0xABCDEF",
        status: "pending_revocation",
        intent: "revoke",
        initiated_at: DateTime.utc_now()
      })

      assert cs.changes.address == "0xabcdef"
    end

    test "rejects unknown status and intent" do
      cs = Status.changeset(%Status{}, %{
        address: "0xabc",
        status: "bogus",
        intent: "revoke",
        initiated_at: DateTime.utc_now()
      })

      refute cs.valid?
      assert {"is invalid", _} = cs.errors[:status]

      cs2 = Status.changeset(%Status{}, %{
        address: "0xabc",
        status: "pending_revocation",
        intent: "nope",
        initiated_at: DateTime.utc_now()
      })

      refute cs2.valid?
      assert {"is invalid", _} = cs2.errors[:intent]
    end
  end

  describe "Confirmer.confirm/1" do
    test "flips pending_revocation to enforced when a confirmed revocation event exists" do
      persist_status(%{
        address: "0xa",
        status: "pending_revocation",
        intent: "revoke",
        initiated_at: DateTime.utc_now()
      })

      {:ok, _} = ChainEvents.persist_events([compliance_event("0xa", false, 1, 0)])
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 1_000_000)

      Confirmer.confirm(@chain_id)

      status = Repo.get_by(Status, address: "0xa")
      assert status.status == "enforced"
      refute is_nil(status.confirmed_at)
    end

    test "flips pending_reinstate to enforced when a confirmed whitelist event exists" do
      persist_status(%{
        address: "0xb",
        status: "pending_reinstate",
        intent: "reinstate",
        initiated_at: DateTime.utc_now()
      })

      {:ok, _} = ChainEvents.persist_events([compliance_event("0xb", true, 1, 0)])
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 1_000_000)

      Confirmer.confirm(@chain_id)

      assert Repo.get_by(Status, address: "0xb").status == "enforced"
    end

    test "does not enforce a revocation when only an UNconfirmed event exists" do
      persist_status(%{
        address: "0xc",
        status: "pending_revocation",
        intent: "revoke",
        initiated_at: DateTime.utc_now()
      })

      # Persisted but NOT confirmed.
      {:ok, _} = ChainEvents.persist_events([compliance_event("0xc", false, 1, 0)])

      Confirmer.confirm(@chain_id)

      assert Repo.get_by(Status, address: "0xc").status == "pending_revocation"
    end

    test "does not enforce when the event whitelist value contradicts the intent" do
      # intent: revoke expects whitelisted=false, but event says true
      persist_status(%{
        address: "0xd",
        status: "pending_revocation",
        intent: "revoke",
        initiated_at: DateTime.utc_now()
      })

      {:ok, _} = ChainEvents.persist_events([compliance_event("0xd", true, 1, 0)])
      {:ok, _} = ChainEvents.confirm_through(@chain_id, 1_000_000)

      Confirmer.confirm(@chain_id)

      assert Repo.get_by(Status, address: "0xd").status == "pending_revocation"
    end
  end

  describe "Submitter dispatch" do
    test "routes to the configured implementation module" do
      # The default impl is documented as NodeSubmitter.
      assert Submitter.impl() == NodeSubmitter
    end
  end

  describe "TokenLedger.Compliance context" do
    test "initiate_revocation creates pending_revocation off-chain-first" do
      {:ok, status} = TokenLedger.Compliance.initiate_revocation("0xAbC")
      assert status.status == "pending_revocation"
      assert status.intent == "revoke"
      assert status.address == "0xabc"
      assert Repo.get_by(Status, address: "0xabc").status == "pending_revocation"
    end

    test "initiate_reinstate creates pending_reinstate" do
      {:ok, status} = TokenLedger.Compliance.initiate_reinstate("0xDeF")
      assert status.status == "pending_reinstate"
      assert status.intent == "reinstate"
    end

    test "re-initiating overwrites intent and resets submission fields" do
      {:ok, _} = TokenLedger.Compliance.initiate_revocation("0x123")
      Repo.update_all(from(s in Status, where: s.address == "0x123"),
        set: [submitted_tx_hash: "0xabc", submitted_at: DateTime.utc_now()]
      )

      {:ok, updated} = TokenLedger.Compliance.initiate_reinstate("0x123")
      assert updated.status == "pending_reinstate"
      assert updated.submitted_tx_hash == nil
      assert updated.submitted_at == nil
    end

    test "Confirmer is chain-scoped" do
      persist_status(%{
        address: "0xe",
        status: "pending_revocation",
        intent: "revoke",
        initiated_at: DateTime.utc_now()
      })

      other_chain = @chain_id + 1

      {:ok, _} =
        ChainEvents.persist_events([
          Map.put(compliance_event("0xe", false, 1, 0), :chain_id, other_chain)
        ])

      {:ok, _} = ChainEvents.confirm_through(other_chain, 1_000_000)

      Confirmer.confirm(@chain_id)

      assert Repo.get_by(Status, address: "0xe").status == "pending_revocation"
    after
      Repo.delete_all(from(e in Event, where: e.chain_id == ^(@chain_id + 1)))
    end
  end
end
