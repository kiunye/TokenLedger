defmodule TokenLedger.Projection do
  @moduledoc """
  Derives domain state from the finalized event log (design decisions 1-4, 8).

  The projection consumes *only* confirmed, non-orphaned events through a
  durable `(block_number, log_index)` checkpoint, applying them in log order,
  one transaction per batch. Balances and the accounts whitelist mirror are
  materialized; `rebuild/1` wipes and replays from zero, doubling as the repair
  primitive and the equivalence proof against incremental application.

  > Single-chain scope: the `balances` and `accounts` tables are keyed by
  > address only (per architecture §3.2). Multi-chain coexistence is a documented
  > non-goal of Phase 4 (see design.md); in a single-chain deployment `rebuild/1`
  > safely wipes and re-derives all derived rows for the chain.
  """
  import Ecto.Query

  alias Ecto.Changeset, as: Changeset
  alias TokenLedger.Accounts.Account
  alias TokenLedger.ChainEvents
  alias TokenLedger.Projections.Balance
  alias TokenLedger.Projections.Checkpoint
  alias TokenLedger.Repo

  @zero_address "0x0000000000000000000000000000000000000000"
  @initial_cursor %{block_number: -1, log_index: -1}

  @doc """
  Applies one ordered batch of confirmed events past the checkpoint and advances
  the checkpoint inside the same transaction. Returns
  `{:ok, applied_count, new_cursor}`. An empty batch is a no-op
  `{:ok, 0, cursor}`.

  Crash safety (design decision 2): event application and checkpoint advance
  share one `Repo.transaction`, so a crash between them replays deterministically
  — the same rows, the same upserts, the same arithmetic.
  """
  @spec apply_batch(integer(), pos_integer()) ::
          {:ok, non_neg_integer(), %{block_number: integer(), log_index: integer()}}
  def apply_batch(chain_id, limit) when limit > 0 do
    result =
      Repo.transaction(fn ->
        cursor = get_cursor(chain_id)
        events = ChainEvents.confirmed_since(chain_id, cursor, limit)

        case events do
          [] ->
            {0, cursor}

          events ->
            apply_events(events)
            new_cursor = last_identity(events)
            set_checkpoint(chain_id, new_cursor)
            {length(events), new_cursor}
        end
      end)

    case result do
      {:ok, {count, cursor}} -> {:ok, count, cursor}
      {:error, _} = err -> err
    end
  end

  @doc """
  Wipes derived rows for `chain_id` (accounts, balances, checkpoint) and replays
  every confirmed event from zero in batches of `rebuild_batch_size`. Used as the
  repair primitive for out-of-band corruption and as the equivalence reference
  for the incremental-application property test.
  """
  @spec rebuild(integer(), keyword()) :: {:ok, non_neg_integer()}
  def rebuild(chain_id, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, 500)

    Repo.transaction(fn ->
      Repo.delete_all(Balance)
      Repo.delete_all(Account)
      Repo.delete_all(from(c in Checkpoint, where: c.chain_id == ^chain_id))

      do_rebuild(chain_id, @initial_cursor, batch_size, 0)
    end)
  end

  # --- internal -------------------------------------------------------------

  defp do_rebuild(chain_id, cursor, batch_size, acc) do
    case ChainEvents.confirmed_since(chain_id, cursor, batch_size) do
      [] ->
        {:ok, acc}

      events ->
        apply_events(events)
        new_cursor = last_identity(events)
        set_checkpoint(chain_id, new_cursor)
        do_rebuild(chain_id, new_cursor, batch_size, acc + length(events))
    end
  end

  defp get_cursor(chain_id) do
    case Repo.get(Checkpoint, chain_id) do
      nil -> @initial_cursor
      %{last_block_number: b, last_log_index: l} -> %{block_number: b, log_index: l}
    end
  end

  defp set_checkpoint(chain_id, %{block_number: b, log_index: l}) do
    case Repo.get(Checkpoint, chain_id) do
      nil ->
        %Checkpoint{chain_id: chain_id, last_block_number: b, last_log_index: l}
        |> Repo.insert!()

      %Checkpoint{} = c ->
        Repo.update!(
          Changeset.change(c, last_block_number: b, last_log_index: l)
        )
    end
  end

  defp last_identity(events) do
    last = List.last(events)
    %{block_number: last.block_number, log_index: last.log_index}
  end

  # Folds one ordered batch into aggregate writes, then issues them in a single
  # pass: ensure accounts, mirror whitelist, upsert balances.
  defp apply_fold(events) do
    Enum.reduce(events, {%{}, %{}, %{}, MapSet.new()}, fn e, acc ->
      fold_event(e, acc)
    end)
  end

  defp apply_events(events) do
    {deltas, touch_block, whitelist, seen_accounts} = apply_fold(events)

    ensure_accounts(MapSet.to_list(seen_accounts))
    apply_whitelist(whitelist)

    # Single writer (worker runs at concurrency 1), so a read-modify-write per
    # address is safe and keeps the arithmetic in Elixir where it is trivially
    # correct. The whole batch is one transaction, so a crash replays it.
    for {address, delta} <- deltas, not Decimal.eq?(delta, Decimal.new(0)) do
      as_of = Map.fetch!(touch_block, address)

      case Repo.get(Balance, address) do
        nil ->
          %Balance{account_address: address, amount: delta, as_of_block: as_of}
          |> Repo.insert!()

        %Balance{} = b ->
          new_amount = Decimal.add(b.amount, delta)
          new_as_of = max(b.as_of_block, as_of)
          Repo.update!(Changeset.change(b, amount: new_amount, as_of_block: new_as_of))
      end
    end

    :ok
  end

  defp apply_whitelist(whitelist) when map_size(whitelist) == 0, do: :ok

  defp apply_whitelist(whitelist) do
    {to_true, to_false} = Enum.split_with(Map.to_list(whitelist), fn {_addr, v} -> v end)

    unless Enum.empty?(to_true) do
      addrs = Enum.map(to_true, fn {a, _} -> a end)

      Repo.update_all(from(a in Account, where: a.address in ^addrs), set: [whitelisted: true])
    end

    unless Enum.empty?(to_false) do
      addrs = Enum.map(to_false, fn {a, _} -> a end)

      Repo.update_all(from(a in Account, where: a.address in ^addrs), set: [whitelisted: false])
    end
  end

  defp fold_event(%{event_type: "transfer"} = e, {deltas, touch, wl, seen}) do
    from = e.payload["from"]
    to = e.payload["to"]
    amount = Decimal.new(e.payload["amount"])
    block = e.block_number

    {deltas, seen} =
      if from == @zero_address do
        # Mint: credit recipient only; zero address is never an account/balance.
        {credit(deltas, to, amount), MapSet.put(seen, to)}
      else
        deltas = deltas |> debit(from, amount) |> credit(to, amount)
        seen = seen |> MapSet.put(from) |> MapSet.put(to)
        {deltas, seen}
      end

    touch = touch_block(touch, from, block) |> touch_block(to, block)
    {deltas, touch, wl, seen}
  end

  defp fold_event(%{event_type: "compliance_updated"} = e, {deltas, touch, wl, seen}) do
    address = e.payload["account"]
    whitelisted = e.payload["whitelisted"]
    block = e.block_number

    wl = Map.put(wl, address, whitelisted)
    seen = MapSet.put(seen, address)
    touch = touch_block(touch, address, block)
    {deltas, touch, wl, seen}
  end

  defp fold_event(_e, acc), do: acc

  defp credit(deltas, @zero_address, _amount), do: deltas
  defp credit(deltas, address, amount), do: Map.update(deltas, address, amount, &Decimal.add(&1, amount))

  defp debit(deltas, @zero_address, _amount), do: deltas
  defp debit(deltas, address, amount), do: Map.update(deltas, address, Decimal.negate(amount), &Decimal.sub(&1, amount))

  defp touch_block(touch, @zero_address, _block), do: touch
  defp touch_block(touch, address, block), do: Map.update(touch, address, block, &max(&1, block))

  defp ensure_accounts([]), do: :ok

  defp ensure_accounts(addresses) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(addresses, &%{address: &1, inserted_at: now, updated_at: now})

    Repo.insert_all(Account, rows, on_conflict: :nothing)
  end
end
