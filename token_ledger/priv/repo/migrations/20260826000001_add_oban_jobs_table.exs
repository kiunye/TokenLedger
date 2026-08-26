defmodule TokenLedger.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  @doc """
  Creates the `oban_jobs` table (and supporting indexes) for scheduled
  reconciliation runs (design decision 6). Uses Oban's bundled migration so the
  schema tracks the installed Oban version.
  """
  def up, do: Oban.Migration.up()

  def down, do: Oban.Migration.down()
end
