defmodule TokenLedger.RPC.ConnectionPool do
  @moduledoc """
  Supervised executor for JSON-RPC calls with a bounded retry/backoff policy.

  Every RPC request flows through `execute/2` in this process, so transient
  node failures (connection refused, timeouts, HTTP 5xx) are retried with
  exponential backoff capped at `:backoff_max_ms` rather than surfacing to
  the listener mid-cycle. When attempts are exhausted the error is returned
  to the caller; the poll loop simply tries again on its next tick instead of
  hot-looping or crashing (spec: transient RPC failure tolerance).

  The process is registered under its own name so it sits first under
  `TokenLedger.Sepolia.Supervisor` (:rest_for_one): if this process ever
  dies, the event listener is restarted alongside it and resumes from the
  last persisted block — never limping on a broken connection. HTTP
  connection pooling itself stays delegated to Finch underneath ethereumex;
  this GenServer owns policy and serialization of chain access.
  """

  use GenServer
  require Logger

  alias TokenLedger.ChainConfig

  @call_timeout 30_000
  @name __MODULE__

  @type policy :: %{
          required(:attempts) => pos_integer(),
          required(:base_ms) => non_neg_integer(),
          required(:max_ms) => non_neg_integer()
        }

  def start_link(opts \\ []) do
    GenServer.start_link(
      __MODULE__,
      Keyword.get(opts, :policy, ChainConfig.retry_policy()),
      name: Keyword.get(opts, :name, @name)
    )
  end

  @doc """
  Runs `fun` (a zero-arity closure over one JSON-RPC call) under the retry
  policy and returns its result. `label` names the call in logs.
  """
  @spec execute((-> {:ok, term()} | {:error, term()}), atom() | String.t()) ::
          {:ok, term()} | {:error, term()}
  def execute(fun, label) do
    GenServer.call(@name, {:execute, fun, label}, @call_timeout)
  end

  @doc """
  Pure retry engine: applies `runner/0` up to `policy.attempts` times,
  sleeping exponentially (`base_ms * 2^n`, capped at `policy.max_ms`)
  between attempts. Public so the policy is unit-testable without a node.
  """
  @spec run_with_retries((-> {:ok, term()} | {:error, term()}), policy()) ::
          {:ok, term()} | {:error, term()}
  def run_with_retries(runner, policy) do
    attempt(runner, policy, 1, nil)
  end

  @impl true
  def init(policy) do
    {:ok, %{policy: policy}}
  end

  @impl true
  def handle_call({:execute, fun, label}, _from, state) do
    result = run_with_retries(fun, state.policy)
    maybe_log_failure(label, result)
    {:reply, result, state}
  end

  defp attempt(runner, policy, attempt, last_error)

  defp attempt(_runner, policy, attempt, last_error) when attempt > policy.attempts do
    {:error, last_error}
  end

  defp attempt(runner, policy, attempt, _last_error) do
    case runner.() do
      {:ok, _} = ok ->
        ok

      {:error, reason} ->
        Process.sleep(backoff_ms(policy, attempt))
        attempt(runner, policy, attempt + 1, reason)
    end
  end

  defp backoff_ms(policy, attempt) do
    min(policy.base_ms * Integer.pow(2, attempt - 1), policy.max_ms)
  end

  defp maybe_log_failure(label, {:error, reason}) do
    Logger.warning("RPC #{inspect(label)} failed after retries: #{inspect(reason)}")
  end

  defp maybe_log_failure(_label, {:ok, _}), do: :ok
end
