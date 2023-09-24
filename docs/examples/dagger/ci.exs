#!/usr/bin/env elixir

Mix.install([{:dagger, "~> 0.8.2"}])

elixir_version = "1.15.4"
erlang_version = "26.0.2"
alpine_version = "3.18.2"

client = Dagger.connect!()
host = Dagger.Client.host(client)

toolchain =
  client
  |> Dagger.Client.container()
  |> Dagger.Container.from("hexpm/elixir:#{elixir_version}-erlang-#{erlang_version}-alpine-#{alpine_version}")
  |> Dagger.Container.with_exec(~w[apk add --no-cache git build-base])
  |> Dagger.Container.with_exec(~w[mix local.rebar --force])
  |> Dagger.Container.with_exec(~w[mix local.hex --force])

deps =
  toolchain
  |> Dagger.Container.with_workdir("/code")
  |> Dagger.Container.with_file("mix.exs", Dagger.Host.file(host, "mix.exs"))
  |> Dagger.Container.with_file("mix.lock", Dagger.Host.file(host, "mix.lock"))
  |> Dagger.Container.with_exec(~w[mix deps.get])
  |> Dagger.Container.with_exec(~w[mix deps.get --check-unused])
  |> then(fn toolchain ->
    Enum.reduce(["dev", "test"], toolchain, fn mix_env, toolchain ->
      toolchain
      |> Dagger.Container.with_env_variable("MIX_ENV", mix_env)
      |> Dagger.Container.with_exec(~w[mix deps.compile])
    end)
  end)
  |> Dagger.Sync.sync()

  Dagger.close(client)
