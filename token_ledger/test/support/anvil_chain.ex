defmodule TokenLedger.Test.AnvilChain do
@moduledoc """
Test-only manager for one local Anvil node.

Started detached (`GenServer.start/3`, deliberately not `start_link`) so it
survives the death of the ExUnit setup process that launched it: ports die
with their owner, and the owner of `setup_all` is not guaranteed to outlive
the module's tests. The integration case stops the node in an `on_exit`
hook. Teardown uses `taskkill /T /F` on Windows and `kill -9` on
Linux/Unix so the spawned executable is reliably reaped.
"""

  use GenServer

  alias TokenLedger.Test.Harness

  @ready_timeout 30_000

  def start(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)

    case GenServer.start(__MODULE__, opts, name: name) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  @doc "Idempotently stops the managed node and its OS process tree."
  def stop(server \\ __MODULE__) do
    case GenServer.whereis(server) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  @doc "HTTP JSON-RPC URL of the managed node."
  def rpc_url(server \\ __MODULE__) do
    GenServer.call(server, :rpc_url)
  end

  @doc "Blocks until the node answers eth_blockNumber, deadline-bounded."
  def wait_ready(timeout \\ @ready_timeout) do
    url = rpc_url()

    Harness.wait_until!(
      timeout,
      fn ->
        match?({:ok, _}, Ethereumex.HttpClient.eth_block_number(url: url))
      end,
      "anvil became ready"
    )
  end

  @impl true
  def init(_opts) do
    exe = find_anvil!()
    port_number = free_port()

    port =
      Port.open({:spawn_executable, exe}, [
        :binary,
        :exit_status,
        :hide,
        args: ["--port", Integer.to_string(port_number)]
      ])

    {:ok, %{port: port, rpc_url: "http://127.0.0.1:#{port_number}"}}
  end

  @impl true
  def handle_call(:rpc_url, _from, state) do
    {:reply, state.rpc_url, state}
  end

  @impl true
  def terminate(_reason, %{port: port}) do
    case Port.info(port, :os_pid) do
      {:os_pid, os_pid} ->
        kill_os_pid(os_pid)

      nil ->
        :ok
    end

    # The port is dead or its process was killed; close it idempotently.
    try do
      Port.close(port)
    rescue
      _ -> :ok
    end

    :ok
  end

  # Kill the spawned OS process tree. taskkill /T /F is Windows-only;
  # on Linux/Unix a plain SIGKILL via kill achieves the same reaping.
  defp kill_os_pid(os_pid) do
    if System.type() == :windows do
      System.cmd("taskkill", ["/PID", Integer.to_string(os_pid), "/T", "/F"],
        stderr_to_stdout: true
      )
    else
      System.cmd("kill", ["-9", Integer.to_string(os_pid)])
    end
  end

  defp find_anvil! do
    System.find_executable("anvil") ||
      foundry_fallback("anvil.exe") ||
      raise("anvil not found on PATH or in ~/.foundry/bin")
  end

  defp foundry_fallback(exe_name) do
    candidate = Path.expand("~/.foundry/bin/#{exe_name}")
    if File.exists?(candidate), do: candidate
  end

  # Ask the kernel for a free ephemeral port; anvil binds it moments later.
  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(socket)
    :gen_tcp.close(socket)
    port
  end
end
