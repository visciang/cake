defmodule Cake.MixProject do
  use Mix.Project

  def project do
    [
      app: :cake,
      version: System.get_env("CAKE_VERSION", "0.0.0"),
      elixir: "~> 1.15",
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        docs: :dev
      ],
      test_coverage: [
        tool: ExCoveralls
      ],
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      escript: [
        main_module: Cake,
        emu_args: "-noinput +B"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:optimus, github: "visciang/optimus"},
      {:nimble_parsec, "~> 1.3"},
      {:excoveralls, "~> 0.12", only: [:test]},
      {:ex_doc, "~> 0.16", only: [:dev], runtime: false},
      {:credo, "~> 1.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.0", only: :test}
    ]
  end
end
