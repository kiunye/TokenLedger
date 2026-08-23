defmodule TokenLedger.MixProject do
  use Mix.Project

  def project do
    [
      app: :token_ledger,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def cli do
    [preferred_envs: [credo: :test]]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {TokenLedger.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Persistence
      {:ecto, "~> 3.14"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, ">= 0.22.4"},
      # Chain access
      {:ethereumex, "~> 0.14"},
      {:ex_abi, "~> 0.8"},
      {:ex_keccak, ">= 0.7.8"},
      # JSON (JSON-RPC payloads, jsonb encoding)
      {:jason, "~> 1.4"}
    ] ++ dev_test_deps()
  end

  defp dev_test_deps do
    if Mix.env() in [:dev, :test] do
      [
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:ex_slop, "~> 0.4", only: [:dev, :test], runtime: false},
        {:reach, "~> 2.8", only: [:dev, :test], runtime: false}
      ]
    else
      []
    end
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]

  defp elixirc_paths(_), do: ["lib"]
end
