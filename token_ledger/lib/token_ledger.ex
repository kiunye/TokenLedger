defmodule TokenLedger do
  @moduledoc """
  Token Ledger indexer: turns every emitted `TokenRegistry` event into a
  durable, gap-free row in the `chain_events` event log (architecture §3.2).

  Module layout:

  - `TokenLedger.Application` — OTP entry point
  - `TokenLedger.ChainSupervisor` / `TokenLedger.Sepolia.Supervisor` — supervision tree (§4.3)
  - `TokenLedger.RPC.Client` — the single JSON-RPC seam
  - `TokenLedger.RPC.ConnectionPool` — bounded retry/backoff executor
  - `TokenLedger.ChainEventListener` — poll-based range ingestion
  - `TokenLedger.ChainEvents` + `TokenLedger.ChainEvents.Event` — persistence boundary
  - `TokenLedger.ChainEvents.Decoder` — pure topic0 → payload decoding
  """
end
