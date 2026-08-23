defmodule TokenLedger.Test.Harness do
  @moduledoc """
  Integration-harness helpers: deadline-bounded condition polling (never
  sleep-tuned), Foundry load-script invocation with machine-readable result
  parsing, and direct node queries that bypass the app's RPC seam.
  """

  alias TokenLedger.RPC.Client

  @anvil_key "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

  @doc """
  Polls `fun` every `interval_ms` until it returns true or the deadline in
  milliseconds elapses. Returns `:ok` or `{:error, :timeout}` — callers turn
  timeouts into assertions, never into sleeps.
  """
  @spec wait_until(pos_integer(), (-> boolean()), pos_integer()) :: :ok | {:error, :timeout}
  def wait_until(deadline_ms, fun, interval_ms \\ 100) do
    deadline = System.monotonic_time(:millisecond) + deadline_ms

    do_wait_until(fun, deadline, interval_ms)
  end

  @doc "Like `wait_until/3` but flunks the current test on timeout."
  @spec wait_until!(pos_integer(), (-> boolean()), String.t(), pos_integer()) :: :ok
  def wait_until!(deadline_ms, fun, label, interval_ms \\ 100) do
    case wait_until(deadline_ms, fun, interval_ms) do
      :ok ->
        :ok

      {:error, :timeout} ->
        raise ExUnit.AssertionError,
          message: "deadline elapsed waiting for: #{label}",
          expr: label
    end
  end

  defp do_wait_until(fun, deadline, interval_ms) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        {:error, :timeout}
      else
        Process.sleep(interval_ms)
        do_wait_until(fun, deadline, interval_ms)
      end
    end
  end

  @doc "Repo root (the Foundry project), so scripts run with relative paths."
  def repo_root do
    Path.expand("../../..", __DIR__)
  end

  def anvil_broadcast_key, do: @anvil_key

  @doc """
  Runs `script/LoadEvents.s.sol` against the given RPC URL.

  Options:
    - `:phase` — LOAD_PHASE value (0 full, 1 grants+mints+foreign, 2
      toggles+transfers, 3 deploy-only)
    - `:registry` — REGISTRY_ADDR to reuse a previous deployment

  Returns parsed machine-readable output; raises on failure or missing lines.
  """
  @spec run_load_script(String.t(), keyword()) ::
          %{
            registry_address: String.t(),
            foreign_address: String.t(),
            expected_events: non_neg_integer()
          }
  def run_load_script(rpc_url, opts) do
    overrides =
      %{"LOAD_PHASE" => Integer.to_string(Keyword.fetch!(opts, :phase))}
      |> maybe_put("REGISTRY_ADDR", opts[:registry])

    env = Map.merge(System.get_env(), overrides)

    {output, exit_status} =
      System.cmd(
        find_forge!(),
        [
          "script",
          "script/LoadEvents.s.sol",
          "--tc",
          "LoadEvents",
          "--rpc-url",
          rpc_url,
          "--broadcast",
          "--private-key",
          @anvil_key
        ],
        cd: repo_root(),
        env: env,
        stderr_to_stdout: true,
        into: ""
      )

    if exit_status != 0 do
      raise "LoadEvents.s.sol failed (exit #{exit_status}):\n#{output}"
    end

    %{
      registry_address:
        parse_line!(output, ~r/REGISTRY_ADDR=(0x[0-9a-fA-F]{40})/, "REGISTRY_ADDR"),
      foreign_address: parse_line!(output, ~r/FOREIGN_ADDR=(0x[0-9a-fA-F]{40})/, "FOREIGN_ADDR"),
      expected_events:
        parse_line!(output, ~r/EXPECTED_EVENTS=(\d+)/, "EXPECTED_EVENTS") |> String.to_integer()
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp parse_line!(output, regex, name) do
    case Regex.run(regex, output) do
      [_, capture] -> capture
      nil -> raise "LoadEvents.s.sol output missing #{name}. Output:\n#{output}"
    end
  end

  @doc "Current chain height via direct node call."
  def height!(rpc_url) do
    {:ok, quantity} = Ethereumex.HttpClient.eth_block_number(url: rpc_url)
    Client.quantity_to_integer!(quantity)
  end

  @doc "eth_getLogs straight against the node, bypassing the app's RPC pool."
  def logs(rpc_url, filter) do
    Ethereumex.HttpClient.eth_get_logs(filter, url: rpc_url)
  end

  defp find_forge! do
    System.find_executable("forge") ||
      foundry_fallback("forge.exe") ||
      raise("forge not found on PATH or in ~/.foundry/bin")
  end

  defp foundry_fallback(exe_name) do
    candidate = Path.expand("~/.foundry/bin/#{exe_name}")
    if File.exists?(candidate), do: candidate
  end
end
