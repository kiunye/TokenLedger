defmodule TokenLedgerWeb.Plugs.RateLimiter do
  @moduledoc """
  Per-IP API request throttle backed by Hammer (ETS in dev/test).

  The `:api` pipeline runs this plug before any controller dispatch. The cap
  is intentionally generous for a portfolio project — 100 requests per 60s
  per remote_ip — enough to keep a runaway script from monopolising the
  endpoint while leaving normal interactive traffic well under the limit.

  Failure mode: open. If Hammer is unavailable or throws, the request
  continues. Production should log and alert on this; for now it never blocks
  a real user on transient storage hiccups.
  """

  import Plug.Conn
  require Logger

  @behaviour Plug

  @scale_ms 60_000
  @capacity 100

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    ip = remote_ip(conn)

    case Hammer.check_rate({:api_request, ip}, @scale_ms, @capacity) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(429, ~s({"error":"rate_limited","limit":#{@capacity},"window_seconds":60}))
        |> halt()

      {:error, reason} ->
        Logger.warning("RateLimiter: hammer failed open: #{inspect(reason)}")
        conn
    end
  end

  # Fall back to connection.remote_ip (the peer_ip when behind a proxy)
  # because conn.remote_ip is set per the configured remote_ip resolver;
  # in test/dev we have no proxy, so this matches the actual socket peer.
  defp remote_ip(conn) do
    case conn.remote_ip do
      {a, b, c, d} -> "#{a}.#{b}.#{c}.#{d}"
      {a, b, c, d, e, f, g, h} ->
        "#{Integer.to_string(a, 16)}:#{Integer.to_string(b, 16)}:#{Integer.to_string(c, 16)}:#{Integer.to_string(d, 16)}:" <>
          "#{Integer.to_string(e, 16)}:#{Integer.to_string(f, 16)}:#{Integer.to_string(g, 16)}:#{Integer.to_string(h, 16)}"
    end
  end
end
