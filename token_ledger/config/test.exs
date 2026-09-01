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
  poll_interval_ms: 200,
  owner_address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

# Integration tests own the chain supervision lifecycle: they start it only
# after Anvil is up and the contract address is known. Unit tests never need
# a chain at all.
config :token_ledger, start_chain_supervisor: false

# Keep test output focused on failures.
config :logger, level: :warning

# Phoenix endpoint for test: does not start an HTTP server by default.
config :token_ledger, TokenLedgerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "d36addeaaeb9bf5f21cd3d83817615851cb78af2f06a7231d3e0b27670d09831a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2",
  server: false
