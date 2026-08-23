defmodule TokenLedger.ChainSupervisor do
  @moduledoc """
  Top of the per-deployment chain supervision (architecture §4.3).

  `:one_for_one`: a future second chain's subtree crashing must never touch
  Sepolia's. Today it supervises exactly one subtree; Phases 3–4 append
  siblings without reshaping.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl true
  def init(_opts) do
    Supervisor.init([TokenLedger.Sepolia.Supervisor], strategy: :one_for_one)
  end
end
