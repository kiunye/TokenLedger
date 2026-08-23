defmodule TokenLedger.ChainEvents.DecoderTest do
  use ExUnit.Case, async: true

  alias TokenLedger.ChainEvents.Decoder

  @zero_address "0x0000000000000000000000000000000000000000"
  @alice "0x1111111111111111111111111111111111111111"
  @bob "0xAbCdEF0123456789AbCdEF0123456789aBCdEf01"

  describe "decode/1 Transfer" do
    test "mint decodes as transfer from the zero address" do
      log = %{
        "address" => "0xabc",
        "topics" => [
          Decoder.transfer_topic0(),
          address_topic(@zero_address),
          address_topic(@alice)
        ],
        "data" => uint_data(1000)
      }

      assert {:ok, "transfer", payload} = Decoder.decode(log)

      # Spec: mint scenario — from is the zero-address string, amount a decimal string.
      assert payload["from"] == @zero_address
      assert payload["to"] == @alice
      assert payload["amount"] == "1000"
    end

    test "transfer decodes both parties lowercase with decimal-string amount" do
      amount = 16 ** 63 + 5

      log = %{
        "topics" => [
          Decoder.transfer_topic0(),
          address_topic(String.downcase(@bob)),
          address_topic(@alice)
        ],
        "data" => uint_data(amount)
      }

      assert {:ok, "transfer", payload} = Decoder.decode(log)

      assert payload["from"] == String.downcase(@bob)
      assert payload["to"] == @alice

      # uint256 must survive as an exact decimal string, not a float.
      assert payload["amount"] == Integer.to_string(amount)
    end
  end

  describe "decode/1 ComplianceUpdated" do
    test "grants decode with native boolean true" do
      log = %{
        "topics" => [Decoder.compliance_topic0(), address_topic(@alice)],
        "data" => uint_data(1)
      }

      assert {:ok, "compliance_updated", payload} = Decoder.decode(log)

      assert payload["account"] == @alice
      assert payload["whitelisted"] == true
      assert is_boolean(payload["whitelisted"])
    end

    test "revocations decode with native boolean false" do
      log = %{
        "topics" => [Decoder.compliance_topic0(), address_topic(@bob)],
        "data" => uint_data(0)
      }

      assert {:ok, "compliance_updated", payload} = Decoder.decode(log)

      assert payload["account"] == String.downcase(@bob)
      assert payload["whitelisted"] == false
    end
  end

  describe "payload raw sub-object" do
    test "carries topics and data verbatim" do
      topics = [
        Decoder.transfer_topic0(),
        address_topic(@zero_address),
        address_topic(@alice)
      ]

      data = uint_data(7)

      assert {:ok, "transfer", payload} =
               Decoder.decode(%{"topics" => topics, "data" => data})

      assert payload["raw"] == %{"topics" => topics, "data" => data}
    end
  end

  describe "unknown logs" do
    test "unknown topic0 returns :ignore" do
      log = %{"topics" => ["0x9999"], "data" => "0x"}

      assert Decoder.decode(log) == :ignore
    end

    test "log without topics returns :ignore" do
      assert Decoder.decode(%{"topics" => [], "data" => "0x"}) == :ignore
    end
  end

  defp address_topic(address_40_hex) when byte_size(address_40_hex) == 42 do
    "0x" <> String.duplicate("0", 24) <> String.slice(address_40_hex, 2..41)
  end

  defp uint_data(value) do
    "0x" <> String.pad_leading(Integer.to_string(value, 16), 64, "0")
  end
end
