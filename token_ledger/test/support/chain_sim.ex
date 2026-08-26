defmodule TokenLedger.Test.ChainSim do
  @moduledoc """
  In-memory stand-in shape-matching `TokenLedger.RPC.Client`: module-level
  `height/0` and `get_block/1` backed by one GenServer holding a mutable
  block world. Lets unit tests script clean advances, reorgs of any depth,
  and over-depth forks without a node.
  """

  use GenServer

  # blocks: %{height => %{hash: "0x..", parent_hash: "0x.."}}; tip = max key.
  def start_link(blocks \\ %{}) do
    case GenServer.start_link(__MODULE__, blocks, name: __MODULE__) do
      {:ok, _pid} = ok ->
        ok

      {:error, {:already_started, pid}} ->
        # Reuse the surviving process and reset its world.
        :ok = GenServer.call(__MODULE__, {:set_blocks, blocks})
        {:ok, pid}
    end
  end

  @doc "Replaces the whole world; tip becomes the highest keyed height."
  def set_blocks(blocks), do: GenServer.call(__MODULE__, {:set_blocks, blocks})

  @doc "Current chain height — mirrors `RPC.Client.height/0`."
  def height, do: GenServer.call(__MODULE__, :height)

  @doc "Block header by number — mirrors `RPC.Client.get_block/1`."
  def get_block(number), do: GenServer.call(__MODULE__, {:get_block, number})

  def stop do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end
  end

  @impl true
  def init(blocks), do: {:ok, blocks}

  @impl true
  def handle_call({:set_blocks, blocks}, _from, _old), do: {:reply, :ok, blocks}

  def handle_call(:height, _from, blocks) do
    {:reply, {:ok, blocks |> Map.keys() |> Enum.max()}, blocks}
  end

  def handle_call({:get_block, number}, _from, blocks) do
    reply =
      case Map.fetch(blocks, number) do
        {:ok, block} -> {:ok, Map.put(block, :number, number)}
        :error -> {:ok, nil}
      end

    {:reply, reply, blocks}
  end
end

defmodule TokenLedger.Test.ChainWorld do
  @moduledoc """
  Builders for linear and forked block worlds used with ChainSim.
  Hashes are deterministic per tag suffix so assertions can compare them.
  """

  def linear(count, tag \\ "a") do
    for n <- 0..(count - 1), into: %{} do
      {n, %{hash: hash(tag, n), parent_hash: parent(tag, n)}}
    end
  end

  @doc """
  World where heights `[from..to]` are replaced by a competing chain: same
  parent entering `from`, new hashes inside, extending to `new_tip`.
  """
  def forked(base, from, to, new_tip, tag \\ "b") do
    kept = Map.drop(base, Enum.to_list(from..to))
    entered_parent = entering_parent(base, from)

    replacements =
      for n <- from..new_tip, into: %{} do
        parent =
          if n == from do
            entered_parent
          else
            hash(tag, n - 1)
          end

        {n, %{hash: hash(tag, n), parent_hash: parent}}
      end

    Map.merge(kept, replacements)
  end

  defp entering_parent(base, from) when from > 0 do
    base
    |> Map.get(from - 1, %{hash: hash("a", from - 1)})
    |> Map.fetch!(:hash)
  end

  defp entering_parent(_base, 0), do: "0x0000"

  def hash(tag, n), do: "0x#{tag}#{Integer.to_string(n, 16) |> String.pad_leading(4, "0")}"
  defp parent(_tag, 0), do: "0x0000"
  defp parent(tag, n), do: hash(tag, n - 1)
end
