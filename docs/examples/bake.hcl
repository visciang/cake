variable "elixir_version" {
  default = "1.15.4"
}

variable "erlang_version" {
  default = "26.0.2"
}

variable "alpine_version" {
  default = "3.18.2"
}

variable artifacts_output_dir {
  default = "./output"
}

# IL TARGET (DI DEFAULT) CHE ESEGUE LA PIPELINE
group "default" {
  targets = ["all"]
}

# DEFINISCE:
# - JOB DELLA PIPELINE
# - ESPORTA ARTEFATTI DEI JOB
target "all" {
  output = [artifacts_output_dir]

  contexts = {
    dialyzer = "target:dialyzer"
    format   = "target:format"
    credo    = "target:credo"
    test     = "target:test"
    docs     = "target:docs"
  }

  dockerfile-inline = <<DOCKERFILE
    FROM scratch
    COPY --from=dialyzer /code/.done /.done
    COPY --from=format /code/.done /.done
    COPY --from=credo /code/.done /.done
    COPY --from=test /code/cover /cover
    COPY --from=docs /code/doc /doc
  DOCKERFILE
}

target "toolchain" {
  dockerfile-inline = <<DOCKERFILE
    FROM hexpm/elixir:${elixir_version}-erlang-${erlang_version}-alpine-${alpine_version}
    RUN apk add --no-cache git build-base
    RUN mix local.rebar --force && \
        mix local.hex --force
  DOCKERFILE
}

target "deps" {
  name = "deps-${mix_env}"

  matrix = {
    mix_env = ["dev", "test"]
  }

  contexts = {
    toolchain = "target:toolchain"
  }

  ssh = ["default"]

  dockerfile-inline = <<DOCKERFILE
    FROM toolchain
    WORKDIR /code
    COPY mix.exs mix.lock ./
    RUN --mount=type=ssh mix deps.get
    RUN mix deps.get --check-unused
    RUN MIX_ENV=${mix_env} mix deps.compile
  DOCKERFILE
}

target "compile" {
  name = "compile-${mix_env}"

  contexts = {
    deps = "target:deps-${mix_env}"
  }

  matrix = {
    mix_env = ["dev", "test"]
  }

  dockerfile-inline = <<DOCKERFILE
    FROM deps
    COPY config ./config
    COPY test ./test
    COPY lib ./lib
    COPY .*.exs ./
    RUN MIX_ENV=${mix_env} mix compile --warnings-as-errors
  DOCKERFILE
}

target "dialyzer-plt" {
  contexts = {
    deps = "target:deps-dev"
  }

  dockerfile-inline = <<DOCKERFILE
    FROM deps
    # dialyzer plt under: _build/dev/dialyxir_*.plt*
    RUN mix dialyzer --plt
  DOCKERFILE
}

target "dialyzer" {
  contexts = {
    compile      = "target:compile-dev"
    dialyzer-plt = "target:dialyzer-plt"
  }

  dockerfile-inline = <<DOCKERFILE
    FROM compile
    COPY --from=dialyzer-plt /code/_build/dev/dialyxir_*.plt* ./_build/dev/
    RUN mix dialyzer --no-check
    RUN touch .done
  DOCKERFILE
}

target "format" {
  contexts = {
    compile = "target:compile-dev"
  }

  dockerfile-inline = <<DOCKERFILE
    FROM compile AS format
    RUN mix format --check-formatted
    RUN touch .done
  DOCKERFILE
}

target "credo" {
  contexts = {
    compile = "target:compile-dev"
  }

  dockerfile-inline = <<DOCKERFILE
    FROM compile
    RUN mix format --check-formatted
    RUN touch .done
  DOCKERFILE
}

target "test" {
  contexts = {
    compile = "target:compile-test"
  }

  dockerfile-inline = <<DOCKERFILE
    FROM compile
    RUN mix coveralls.html
  DOCKERFILE
}

target "docs" {
  contexts = {
    compile = "target:compile-dev"
  }

  dockerfile-inline = <<DOCKERFILE
    FROM compile
    COPY README.md ./
    RUN mix docs --formatter=html
  DOCKERFILE
}

# ESEMPIO DI TARGET ESEGUITO SEMPRE (NON CACHED)
# UTILE PER DEFINIRE JOB CHE HANNO SIDE-EFFECT
target "gio" {
  no-cache = true

  dockerfile-inline = <<DOCKERFILE
    FROM alpine
    RUN echo "---------------------------"
  DOCKERFILE
}