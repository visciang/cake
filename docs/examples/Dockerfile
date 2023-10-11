ARG ELIXIR_VERSION=1.15.4
ARG ERLANG_VERSION=26.0.2
ARG ALPINE_VERSION=3.18.2

# FROM alpine AS giovanni
# RUN --mount=type=bind,target=/image/dir ls -l /image/dir/mix.exs

# ---- toolchain ----

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ERLANG_VERSION}-alpine-${ALPINE_VERSION} AS toolchain
RUN apk add --no-cache git build-base
RUN mix local.rebar --force && \
    mix local.hex --force

# ---- deps ----

FROM toolchain AS deps
WORKDIR /code
COPY mix.exs mix.lock ./
RUN --mount=type=ssh mix deps.get
RUN mix deps.get --check-unused
RUN MIX_ENV=dev mix deps.compile && \
    MIX_ENV=test mix deps.compile

# ---- compile ----

FROM deps AS compile
COPY config ./config
COPY test ./test
COPY lib ./lib
COPY .*.exs ./
RUN MIX_ENV=dev mix compile --warnings-as-errors && \
    MIX_ENV=test mix compile --warnings-as-errors

# ---- dialyzer-plt ----

FROM deps AS dialyzer-plt
# dialyzer plt under: _build/dev/dialyxir_*.plt*
RUN mix dialyzer --plt

# ---- dialyzer ----

FROM compile AS dialyzer
COPY --from=dialyzer-plt /code/_build/dev/dialyxir_*.plt* ./_build/dev/
RUN mix dialyzer --no-check
RUN touch .done

# ---- format ----

FROM compile AS format
RUN mix format --check-formatted
RUN touch .done

# ---- credo ----

FROM compile AS credo
ARG ELIXIR_CREDO_OPTS="--strict --all"
RUN mix credo ${ELIXIR_CREDO_OPTS}
RUN touch .done

# ---- test ----

FROM compile AS test
ARG ELIXIR_TEST_CMD="coveralls.html"
RUN mix ${ELIXIR_TEST_CMD}

# ---- docs ----

FROM compile AS docs
COPY README.md ./
RUN mix docs --formatter=html

# ---- release ----

FROM compile AS release
RUN mix release --path=_release

# ---- app ----

# FROM docker.io/library/alpine:${ALPINE_VERSION} as app
# ARG APP_NAME
# ARG EXTRA_PACKAGES=""
# RUN apk add --no-cache busybox ${EXTRA_PACKAGES}
# COPY --from=release /build/_release /app
# RUN ln -s /app/bin/$APP_NAME /app/bin/app
# CMD ["/app/bin/app", "start"]

# ---- all ----

FROM scratch AS all
COPY --from=dialyzer /code/.done /.done
COPY --from=format /code/.done /.done
COPY --from=credo /code/.done /.done
COPY --from=test /code/cover /cover
COPY --from=docs /code/doc /doc
COPY --from=release /code/_release /_release
