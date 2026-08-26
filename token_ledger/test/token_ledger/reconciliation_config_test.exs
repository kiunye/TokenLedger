defmodule TokenLedger.ReconciliationConfigTest do
  # Verifies the Oban wiring that the cron cadence depends on (design decision
  # 6): dev runs the reconciliation queue with a minute cron; test disables
  # both so jobs run only when a test performs them inline.
  use ExUnit.Case, async: true

  @tag :config
  test "dev enables the reconciliation queue and a cron entry" do
    config = Config.Reader.read!("config/dev.exs", env: :dev, imports: [])
    oban = config[:token_ledger][Oban]

    assert oban[:queues] == [reconciliation: 1]
    assert [{cron_expr, TokenLedger.ReconciliationJob}] = oban[:cron][:crontab]
    assert cron_expr == "* * * * *"
  end

  @tag :config
  test "test disables queues and cron (inline-only jobs)" do
    config = Config.Reader.read!("config/config.exs", env: :test, imports: [])
    oban = config[:token_ledger][Oban]

    assert oban[:queues] == false
    assert oban[:cron] == false
  end
end
