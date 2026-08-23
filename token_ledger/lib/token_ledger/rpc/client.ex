defmodule TokenLedger.RPC.Client do
  @moduledoc """
  The single seam for all JSON-RPC access (design decision on clean seams).

  Thin by intent: builds the request, delegates execution to
  `TokenLedger.RPC.ConnectionPool` (which owns the bounded retry/backoff
  policy), and converts hex quantities. Replacing ethereumex is a
  single-file change confined to this module.
  """

  alias TokenLedger.ChainConfig
  alias TokenLedger.ChainEvents.Decoder
  alias TokenLedger.RPC.ConnectionPool

  @type block_number :: non_neg_integer()

  @doc "Current chain height."
  @spec height() :: {:ok, block_number()} | {:error, term()}
  def height do
    ConnectionPool.execute(
      fn -> Ethereumex.HttpClient.eth_block_number(url: url()) end,
      :eth_block_number
    )
    |> case do
      {:ok, quantity} -> {:ok, quantity_to_integer!(quantity)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Logs emitted in `[from_block, to_block]` filtered to the watched contract
  and the two known topic0s. Returns raw string-keyed log maps as delivered
  by the node.
  """
  @spec get_logs(String.t(), block_number(), block_number()) ::
          {:ok, [map()]} | {:error, term()}
  def get_logs(address, from_block, to_block) do
    filter = %{
      "address" => String.downcase(address),
      "fromBlock" => integer_to_quantity(from_block),
      "toBlock" => integer_to_quantity(to_block),
      "topics" => [
        [
          Decoder.transfer_topic0(),
          Decoder.compliance_topic0()
        ]
      ]
    }

    ConnectionPool.execute(
      fn -> Ethereumex.HttpClient.eth_get_logs(filter, url: url()) end,
      :eth_get_logs
    )
  end

  @doc """
  Read-only contract call. `data` is the ABI-encoded calldata including the
  method selector; `block` is a tag (`"latest"`) or hex quantity.
  """
  @spec call(String.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def call(to, data, block \\ "latest") do
    transaction = %{"to" => String.downcase(to), "data" => data}

    ConnectionPool.execute(
      fn -> Ethereumex.HttpClient.eth_call(transaction, block, url: url()) end,
      :eth_call
    )
  end

  @doc "Converts an RPC hex quantity (`\"0x1a\"`) to an integer."
  @spec quantity_to_integer!(term()) :: non_neg_integer()
  def quantity_to_integer!("0x" <> hex) when is_binary(hex) do
    String.to_integer(hex, 16)
  end

  def quantity_to_integer!(other) do
    raise ArgumentError, "expected a hex quantity from RPC, got: #{inspect(other)}"
  end

  @doc "Converts a block number to its RPC hex-quantity form."
  @spec integer_to_quantity(block_number()) :: String.t()
  def integer_to_quantity(number) when is_integer(number) and number >= 0 do
    "0x" <> Integer.to_string(number, 16)
  end

  defp url, do: ChainConfig.rpc_url()
end
