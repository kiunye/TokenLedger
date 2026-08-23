import Config

# Configure the main Ecto repository.
config :token_ledger, ecto_repos: [TokenLedger.Repo]

# Default chain configuration. Values here are safe defaults for a local
# Anvil chain; per-environment files and config/runtime.exs refine them.
# All of these are read through TokenLedger.ChainConfig at runtime.
config :token_ledger,
  chain_id: 31337,
  rpc_url: "http://localhost:8545",
  contract_address: nil,
  start_block: 0,
  poll_interval_ms: 2_000,
  max_chunk_blocks: 2_000,
  # RPC retry policy for transient JSON-RPC failures (bounded backoff)
  retry_attempts: 5,
  backoff_base_ms: 250,
  backoff_max_ms: 8_000,
  # When false, TokenLedger.Application does not start the chain supervision
  # tree (integration tests start it explicitly after their fixtures are up).
  start_chain_supervisor: true

config :logger, level: :info

import_config "#{config_env()}.exs"
