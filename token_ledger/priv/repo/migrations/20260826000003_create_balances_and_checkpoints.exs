defmodule TokenLedger.Repo.Migrations.CreateBalancesAndCheckpoints do
  use Ecto.Migration

  @doc """
  Creates the `balances` projection table and the `projection_checkpoints`
  cursor table (design decision 2).

  `balances.amount` is an unconstrained numeric so uint256 token amounts need no
  scaling; `as_of_block` records the block of the last applied event touching
  the account. `projection_checkpoints` carries the durable (block_number,
  log_index) identity the projection resumes from, keyed per chain.
  """
  def change do
    create table(:balances, primary_key: false) do
      add :account_address, :string, primary_key: true
      add :amount, :numeric, null: false, default: 0
      add :as_of_block, :bigint, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:balances, [:account_address])

    create table(:projection_checkpoints, primary_key: false) do
      add :chain_id, :integer, primary_key: true
      add :last_block_number, :bigint, null: false, default: -1
      add :last_log_index, :integer, null: false, default: -1

      timestamps(type: :utc_datetime, updated_at: true, inserted_at: false)
    end
  end
end
