defmodule Dake.MixProject do
  use Mix.Project

  def project do
    [
      app: :dake,
      version: "0.1.0",
      elixir: "~> 1.15",
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        docs: :dev
      ],
      test_coverage: [tool: ExCoveralls],
      deps: deps(),
      escript: [
        app: nil,
        main_module: Dake
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:nimble_parsec, "~> 1.3", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.12", only: [:test]},
      {:ex_doc, "~> 0.16", only: [:dev], runtime: false},
      {:credo, "~> 1.0", only: [:dev], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
