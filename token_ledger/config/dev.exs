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
  poll_interval_ms: 2_000
