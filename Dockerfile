ARG ELIXIR_VERSION=1.16.1
ARG ELIXIR_ERLANG_VERSION=26.2.2
ARG ELIXIR_ALPINE_VERSION=3.19.1

FROM docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${ELIXIR_ERLANG_VERSION}-alpine-${ELIXIR_ALPINE_VERSION} as build
# ERL_FLAGS="+JPperf true" is a workaround to "fix" the problem of docker cross-platform builds via QEMU.
# REF:  https://elixirforum.com/t/mix-deps-get-memory-explosion-when-doing-cross-platform-docker-build/57157
ENV ERL_FLAGS="+JPperf true"
WORKDIR /code
RUN apk add --no-cache git build-base
RUN mix local.rebar --force && mix local.hex --force
COPY mix.exs mix.lock ./
RUN mix deps.get
RUN mix deps.compile
COPY config ./config
COPY test ./test
COPY lib ./lib
COPY .*.exs ./
ARG CAKE_VERSION=0.0.0
RUN CAKE_VERSION=${CAKE_VERSION} mix escript.build

FROM docker.io/hexpm/elixir:${ELIXIR_VERSION}-erlang-${ELIXIR_ERLANG_VERSION}-alpine-${ELIXIR_ALPINE_VERSION} as cake.app
RUN apk add --no-cache bash git openssh-client docker-cli docker-cli-buildx
RUN mkdir -p -m 0700 ~/.ssh \
    && ssh-keyscan github.com gitlab.com bitbucket.com >> ~/.ssh/known_hosts
COPY --from=build /code/cake /cake
ENTRYPOINT [ "/cake" ]
