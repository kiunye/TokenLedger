defmodule TokenLedgerWeb.Plugs.RateLimiter do
  @moduledoc """
  Per-IP rate limit for the JSON API.

  Keys the Hammer `:single` backend on the client's remote IP (IPv4 and IPv6
  alike, formatted via `:inet.ntoa/1`), allowing `@limit` requests per
  `@scale_ms` millisecond window. Fail-open: a backend error logs a warning
  and lets the request through, so a rate-limiter outage can never take the
  API down.
  """

  import Plug.Conn

  require Logger

  @behaviour Plug

  @limit 100
  @scale_ms 60_000
  @key_prefix "api:"

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    key = @key_prefix <> client_ip(conn)

    case Hammer.check_rate(key, @scale_ms, @limit) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_resp_header("retry-after", retry_after())
        |> put_resp_content_type("application/json")
        |> send_resp(429, Jason.encode!(%{error: "Too many requests"}))
        |> halt()

      {:error, reason} ->
        Logger.warning("rate limiter backend error for #{key}: #{inspect(reason)}; failing open")
        conn
    end
  end

  defp client_ip(conn) do
    remote_ip = conn.remote_ip

    cond do
      is_tuple(remote_ip) -> remote_ip |> :inet.ntoa() |> to_string()
      is_binary(remote_ip) -> remote_ip
      true -> "unknown"
    end
  end

  defp retry_after do
    # The window is a rolling 60s bucket from the first request; a safe
    # conservative retry hint is one second (bounded, deterministic).
    "1"
  end
end