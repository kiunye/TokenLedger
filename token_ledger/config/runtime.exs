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
