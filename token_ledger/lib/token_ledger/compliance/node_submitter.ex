defmodule TokenLedger.Compliance.NodeSubmitter do
  @moduledoc """
  Default submitter implementation (Phase 5): sends `setWhitelisted` calls via
  the JSON-RPC endpoint's unlocked account mechanism.

  The contract's `setWhitelisted(address account, bool status)` selector is
  computed via ABI encoding. The node (Anvil for tests) holds the signing
  key and signs on behalf of the caller — the private key never leaves the
  node's memory (including production nodes using managed wallets or HSMs).

  Design drift note: the approved Phase 5 design described a
  `LocalKeySubmitter` with offline signing and `eth_sendRawTransaction` plus
  explicit nonce management. This implementation uses node-side signing via
  `eth_sendTransaction` with an unlocked account/HSM, which keeps the key out
  of application memory and is the intended production path; the difference is
  a signing-authority placement, not a security downgrade. Kept intentionally
  for Phase 5; revisit explicit-nonce raw-tx path when Phase 7 custody
  requires it.
  """

  alias TokenLedger.ChainConfig
  alias TokenLedger.Compliance.Submitter
  alias TokenLedger.RPC.Client

  @behaviour Submitter

  require Logger

  @sig "setWhitelisted(address,bool)"

  @impl Submitter
  def submit_revocation(address) when is_binary(address) do
    submit_tx(address, false)
  end

  @impl Submitter
  def submit_reinstate(address) when is_binary(address) do
    submit_tx(address, true)
  end

  defp submit_tx(address, whitelisted) do
    with {:ok, address_bin} <- hex_to_bin(address) do
      calldata = encode_calldata(@sig, [address_bin, whitelisted])
      from = ChainConfig.owner_address()
      to = ChainConfig.contract_address!()

      transaction = %{
        "from" => String.downcase(from),
        "to" => String.downcase(to),
        "data" => "0x" <> Base.encode16(calldata, case: :lower)
      }

      case Client.eth_send_transaction(transaction) do
        {:ok, tx_hash} -> {:ok, tx_hash}
        {:error, reason} ->
          Logger.warning("Compliance tx failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp encode_calldata(signature, args) do
    ABI.encode(signature, args)
  end

  defp hex_to_bin(address) when is_binary(address) do
    hex = address |> String.downcase() |> String.trim_leading("0x")

    case Base.decode16(hex, case: :lower) do
      {:ok, <<_::binary-size(20)>> = bin} -> {:ok, bin}
      _ -> {:error, :invalid_address}
    end
  end
end
