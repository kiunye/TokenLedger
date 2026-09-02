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

# Oban base configuration. Environment files refine queues/cron: dev runs the
# reconciliation queue on a 30-second cron (§2.5); test disables both so jobs
# execute only when a test performs them inline.
config :token_ledger, Oban,
  engine: Oban.Engines.Basic,
  repo: TokenLedger.Repo,
  queues: false,
  plugins: false,
  cron: false

config :logger, level: :info

# Hammer rate limiter configuration.
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000, capacity: 100]}

# Phoenix endpoint base configuration (shared across envs).
config :token_ledger, TokenLedgerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: TokenLedgerWeb.ErrorHTML, json: TokenLedgerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: TokenLedger.PubSub,
  live_view: [signing_salt: "token_ledger_live_view"]

import_config "#{config_env()}.exs"
