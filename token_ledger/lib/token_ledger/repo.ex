defmodule TokenLedger.Repo do
  @moduledoc """
  Ecto repository backing the Token Ledger event store.
  """

  use Ecto.Repo,
    otp_app: :token_ledger,
    adapter: Ecto.Adapters.Postgres
end
