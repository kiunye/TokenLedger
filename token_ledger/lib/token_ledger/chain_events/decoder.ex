defmodule TokenLedger.ChainEvents.Decoder do
  @moduledoc """
  Pure topic0 → semantic-payload decoder for the two known event types.

  Dispatches on the log's first topic using `ex_abi` and returns the decoded
  payload with:

  - addresses as lowercase `"0x…"` strings,
  - uint256 amounts as decimal strings (uint256 is JS-unsafe as a number),
  - booleans as native Elixir booleans,
  - a nested `raw` object holding the original `topics`/`data` verbatim for
    auditability (design decision 5).

  Unknown topics return `:ignore` — the caller drops the log. This module
  performs no I/O and touches no other part of the system (design decision
  8), which is what makes it unit-testable without RPC.
  """

  # ABI specification of the two locked events (PROGRESS.md Phase 2 entry
  # notes). Signatures are contract-frozen; changing them is breaking.
  @abi [
    %{
      "type" => "event",
      "name" => "Transfer",
      "anonymous" => false,
      "inputs" => [
        %{"name" => "from", "type" => "address", "indexed" => true},
        %{"name" => "to", "type" => "address", "indexed" => true},
        %{"name" => "amount", "type" => "uint256", "indexed" => false}
      ]
    },
    %{
      "type" => "event",
      "name" => "ComplianceUpdated",
      "anonymous" => false,
      "inputs" => [
        %{"name" => "account", "type" => "address", "indexed" => true},
        %{"name" => "whitelisted", "type" => "bool", "indexed" => false}
      ]
    }
  ]

  @selectors ABI.parse_specification(@abi, include_events?: true)

  @transfer_topic0 "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
  @compliance_topic0 "0x8aa6253d2025a97ac3b67ce2e65b9979a0256b81c6a1efb273ccf0c7365a0aea"

  @type event_type :: String.t()

  @doc "topic0 of `Transfer(address,address,uint256)`."
  def transfer_topic0, do: @transfer_topic0

  @doc "topic0 of `ComplianceUpdated(address,bool)`."
  def compliance_topic0, do: @compliance_topic0

  @doc """
  Decodes one node log (string-keyed map as delivered by eth_getLogs) into
  `{event_type, payload}` where payload carries the semantic fields plus the
  verbatim `raw` sub-object. Returns `:ignore` for unknown topics.
  """
  @spec decode(map()) :: {:ok, event_type(), map()} | :ignore
  def decode(%{"topics" => [topic0 | _] = topics} = log) when is_binary(topic0) do
    case topic0 do
      @transfer_topic0 ->
        {:ok, "transfer", build_payload(log, topics, [:from, :to, :amount])}

      @compliance_topic0 ->
        {:ok, "compliance_updated", build_payload(log, topics, [:account, :whitelisted])}

      _ ->
        :ignore
    end
  end

  def decode(_log), do: :ignore

  defp build_payload(log, topics, field_names) do
    {_selector, values} =
      ABI.Event.find_and_decode(
        @selectors,
        hex_to_bin(topic0(topics)),
        hex_to_bin(Enum.at(topics, 1)),
        hex_to_bin(Enum.at(topics, 2)),
        hex_to_bin(Enum.at(topics, 3)),
        hex_to_bin(Map.get(log, "data")) || <<>>
      )

    decoded =
      values
      |> Enum.map(fn {_name, _type, _indexed?, value} -> normalize_value(value) end)
      |> Enum.zip(field_names)
      |> Map.new(fn {value, name} -> {Atom.to_string(name), value} end)

    Map.put(decoded, "raw", %{
      "topics" => topics,
      "data" => Map.get(log, "data")
    })
  end

  # ex_abi returns addresses as raw 20-byte binaries, uints as integers and
  # bools natively; shape them per design decision 5 here, in one place.
  defp normalize_value(value) when is_binary(value) and byte_size(value) == 20,
    do: format_address(value)

  defp normalize_value(value) when is_integer(value) and value >= 0,
    do: Integer.to_string(value)

  defp normalize_value(value), do: value

  defp format_address(<<_::binary-size(20)>> = address) do
    "0x" <> Base.encode16(address, case: :lower)
  end

  defp topic0([topic0 | _]), do: topic0

  defp hex_to_bin(nil), do: nil

  defp hex_to_bin("0x" <> rest) when rest != "" do
    case Base.decode16(rest, case: :mixed) do
      {:ok, bin} -> bin
      :error -> raise ArgumentError, "invalid hex from RPC: 0x#{rest}"
    end
  end

  defp hex_to_bin(""), do: nil
end
