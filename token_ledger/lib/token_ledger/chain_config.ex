defmodule TokenLedger.ChainConfig do
  @moduledoc """
  Typed access to the chain configuration keys (`:token_ledger` application
  environment). Every consumer goes through here so config shape has exactly
  one definition.
  """

  @chain_id_default 31_337
  @rpc_url_default "http://localhost:8545"
  @start_block_default 0
  @poll_interval_ms_default 2_000
  @max_chunk_blocks_default 2_000
  @retry_attempts_default 5
  @backoff_base_ms_default 250
  @backoff_max_ms_default 8_000
  @confirmation_depth_default 12

  @doc "Chain this app indexes. Schema-ready for future multi-chain."
  def chain_id do
    get(:chain_id, @chain_id_default)
  end

  @doc "JSON-RPC HTTP endpoint of the node."
  def rpc_url do
    get(:rpc_url, @rpc_url_default)
  end

  @doc """
  Watched contract address, lowercased. Raises when unset: without it the
  listener cannot filter logs, so starting silently would be a lie.
  """
  def contract_address! do
    case get(:contract_address, nil) do
      nil ->
        raise ArgumentError,
              "config :token_ledger, :contract_address is not set; the listener refuses to start unconfigured"

      address when is_binary(address) ->
        String.downcase(address)
    end
  end

  @doc "First block ever considered for ingestion (fresh-start cursor)."
  def start_block do
    get(:start_block, @start_block_default)
  end

  @doc "Delay between polling cycles."
  def poll_interval_ms do
    get(:poll_interval_ms, @poll_interval_ms_default)
  end

  @doc "Maximum block span per eth_getLogs call (provider range caps)."
  def max_chunk_blocks do
    get(:max_chunk_blocks, @max_chunk_blocks_default)
  end

  @doc "Blocks of depth before a live event counts as final (architecture §2.5)."
  def confirmation_depth do
    get(:confirmation_depth, @confirmation_depth_default)
  end

  @doc "Bounded retry policy applied by RPC.ConnectionPool."
  def retry_policy do
    %{
      attempts: get(:retry_attempts, @retry_attempts_default),
      base_ms: get(:backoff_base_ms, @backoff_base_ms_default),
      max_ms: get(:backoff_max_ms, @backoff_max_ms_default)
    }
  end

  @owner_address_default "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

  @doc "Address of the token registry owner, used for signing tx submissions."
  def owner_address do
    get(:owner_address, @owner_address_default)
  end

  defp get(key, default) do
    Application.get_env(:token_ledger, key, default)
  end
end
