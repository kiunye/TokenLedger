# Token Ledger

A permissioned tokenized-asset registry: a Solidity contract mints and moves whitelisted tokens on-chain, and an Elixir/OTP backend indexes every event into a reconciled, observable projection of that chain.

## Why this exists

Most blockchain portfolio projects stop at *calling* a smart contract from a web app — that demonstrates wiring, not systems thinking. Token Ledger targets the harder problem underneath any real tokenization platform:

> **The chain is the source of truth. Your backend is a lagging projection of it. The interesting engineering is the reconciliation between those two states.**

So the project is built around three provable behaviors, each demonstrated by automated tests rather than prose:

1. **Events are a write-ahead log, not a cache.** Every on-chain event lands in an append-only log before anything derives meaning from it.
2. **Reorgs are detected and corrected loudly.** A processed block being orphaned triggers rollback-and-reapply you can watch happen (roadmap).
3. **Staleness is visible.** The system reports how far its projection lags the chain instead of showing numbers with no confidence attached (roadmap).

## Architecture at a glance

```
Anvil / Sepolia ──── TokenRegistry.sol  (authoritative state)
        │ JSON-RPC
        ▼
Elixir/OTP indexer ── supervision tree: RPC pool ▸ event listener ▸ …
        │ every event persisted exactly once, idempotently
        ▼
Postgres (chain_events write-ahead log → derived projections)
        │
        ▼
Phoenix LiveView dashboard: balances, transfers, reconciliation health (roadmap)
```

**On-chain** (`src/TokenRegistry.sol`): owner-gated minting to whitelisted recipients only; whitelist enforced on **both sides** of every transfer; revocation **freezes** a balance rather than burning it; typed custom errors; an intentionally ERC-20-shaped surface minus allowance machinery (no trading layer exists). Fully covered by a Foundry suite including a handler-based supply-conservation invariant fuzzer.


## Design choices worth a second look

- **The contract is the security boundary; everything off-chain is UX.** Whitelist rules live on-chain; the future pre-flight simulation endpoint exists to save users gas, never to enforce policy.
- **Idempotency lives in the database.** A unique index on `(chain_id, block_number, log_index)` plus conflict-nothing inserts makes crash-window replays harmless no-ops — dedupe is never trusted to application memory.
- **Freeze, don't burn.** Revoking an address preserves its balance permanently; confiscation isn't a feature anyone asked for.
- **Deliberate failure ordering.** Supervision starts the RPC pool before the listener under `:rest_for_one`, so a dead connection restarts downstream workers instead of letting them limp on stale state.

## Getting started

**Prerequisites:** [Foundry](https://getfoundry.sh), Elixir (recent stable, e.g. via [mise](https://mise.jdx.dev)), Docker.

```bash
# 1. Contract — tests and local chain
forge test
anvil                                   # terminal 1
forge script script/Deploy.s.sol \
  --rpc-url http://localhost:8545 --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80   # anvil default #0

# 2. Database — credentials via Docker secrets (local-only files)
mkdir secrets
# generate a password into secrets/postgres_password.txt (no trailing newline)
docker compose up -d

# 3. Indexer (once Phase 2 lands)
cd token_ledger
mix deps.get && mix ecto.setup && iex -S mix
```

## Repository layout

```
src/                TokenRegistry.sol
test/               Foundry unit + invariant suites
script/             Deploy and load-generation scripts
token_ledger/       Elixir OTP application (indexer)
docker-compose.yml  Postgres 16 for dev/test
secrets/            Local-only credential files — never committed
```
