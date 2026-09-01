import Config

# The Postgres password lives ONLY in the local-only secrets file mounted by
# docker-compose (POSTGRES_PASSWORD_FILE). It is read here at config-load
# time and never hardcoded or committed. See AGENTS.md / handoff notes.
secrets_file = Path.expand("../../secrets/postgres_password.txt", __DIR__)

db_password =
  case File.read(secrets_file) do
    {:ok, content} ->
      String.trim_trailing(content)

    {:error, reason} ->
      raise """
      Cannot read Postgres password from #{inspect(secrets_file)}: #{inspect(reason)}.
      The compose stack mounts it from secrets/postgres_password.txt; that file
      must exist locally (git-excluded) before any mix command touches the DB.
      """
  end

config :token_ledger, TokenLedger.Repo,
  database: "token_ledger_dev",
  username: "postgres",
  password: db_password,
  hostname: "localhost",
  pool_size: 10,
  queue_target: 5_000,
  queue_interval: 20_000

# Local dev chain: docker-compose Postgres + a local Anvil on the default port.
# Deploy the contract, then either export TOKEN_LEDGER_CONTRACT_ADDRESS (picked
# up by config/runtime.exs) or set :contract_address directly before starting.
config :token_ledger,
  chain_id: 31337,
  rpc_url: "http://localhost:8545",
  poll_interval_ms: 2_000,
  contract_address: nil,
  owner_address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

# Reconciliation anti-entropy on the §2.5 cadence. Oban.Cron is minute-
# granular in the pinned version, so the spec's "every 30 seconds" is realized
# as every minute (the exactly-once catch-up property holds at any cadence).
# One runner, no overlap.
config :token_ledger, Oban,
  queues: [reconciliation: 1, compliance: 1],
  cron: [
    crontab: [
      {"* * * * *", TokenLedger.ReconciliationJob},
      {"* * * * *", TokenLedger.Compliance.Job}
    ]
  ]

# Phoenix endpoint for dev: serves on 127.0.0.1:4000 with code reloading off.
# Bandit is the HTTP adapter.
config :token_ledger, TokenLedgerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: false,
  debug_errors: true,
  secret_key_base: "pSTLJEGnY81B2s+o9gR5kjTdVxuFz+y7AganSBk4P2NUv4G58OP1NAenRSSQFwPwTLSxV8cR1k2Q3t4u5v6w7x8y9z0a1b2c3d4e5f==",
  server: true
