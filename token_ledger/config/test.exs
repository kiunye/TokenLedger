import Config

# Same secrets-file discipline as dev: the password is read from the
# local-only file at config-load time, never hardcoded or committed.
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
  database: "token_ledger_test",
  username: "postgres",
  password: db_password,
  hostname: "localhost",
  pool_size: 10,
  queue_target: 5_000,
  queue_interval: 20_000

config :token_ledger,
  chain_id: 31337,
  rpc_url: "http://localhost:8545",
  poll_interval_ms: 200

# Integration tests own the chain supervision lifecycle: they start it only
# after Anvil is up and the contract address is known. Unit tests never need
# a chain at all.
config :token_ledger, start_chain_supervisor: false

# Keep test output focused on failures.
config :logger, level: :warning
