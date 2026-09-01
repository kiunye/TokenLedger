import Config

# Runtime overrides for local development. The contract address is only known
# after `forge script script/Deploy.s.sol` (or the load script) runs, so it
# arrives via environment rather than compile-time config.
if config_env() == :dev do
  case System.get_env("TOKEN_LEDGER_CONTRACT_ADDRESS") do
    nil -> :ok
    "" -> :ok
    address -> config :token_ledger, contract_address: String.downcase(address)
  end
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :token_ledger, TokenLedgerWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true

  if contract = System.get_env("TOKEN_LEDGER_CONTRACT_ADDRESS") do
    config :token_ledger, contract_address: String.downcase(contract)
  end
end
