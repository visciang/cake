
# docker buildx build \
#        --progress=plain \
#        --no-cache-filter=elixir.xxx-example-push \
#        --output=/tmp/output \
#        --file=.dake/Dockerfile \
#        --target=elixir.all .
# docker buildx build \
#        --progress=plain \
#        --output=/tmp/output \
#        --file=.dake/Dockerfile \
#        --target=elixir.all .

# ==== args: ./included/Dakefile --INCLUDED_ARG=xyz ====

ARG INCLUDED_ARG=xyz

# ==== args: ./Dakefile ====

ARG ELIXIR_VERSION=1.15.5
ARG ELIXIR_ERLANG_VERSION=26.0.2
ARG ELIXIR_ALPINE_VERSION=3.18.2

# ==== file: ./included/Dakefile --INCLUDED_ARG=xyz ====

# ---- target: included.toolchain ----

FROM alpine AS included.toolchain
COPY ..dake/dake-include/file.txt .
RUN echo "included.toolchain"
RUN touch /.dake_done

# ---- target: included-target ----

FROM included.toolchain AS included-target
RUN echo "included.target"
RUN touch /.dake_done

# ---- target: included.all ----

FROM scratch AS included.all
COPY --from=included.target /.dake_done /.dake_done
RUN touch /.dake_done

# ==== file: ./Dakefile ====

# ---- target: elixir.toolchain ----

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${ELIXIR_ERLANG_VERSION}-alpine-${ELIXIR_ALPINE_VERSION} AS elixir.toolchain
RUN apk add --no-cache git build-base
RUN mix local.rebar --force && \
    mix local.hex --force
RUN touch /.dake_done

# ---- target: elixir.deps ----

FROM elixir.toolchain AS elixir.deps
WORKDIR /code
COPY mix.exs mix.lock* ./
RUN --mount=type=ssh mix deps.get
RUN mix deps.get --check-unused
RUN MIX_ENV=dev mix deps.compile && \
    MIX_ENV=test mix deps.compile
RUN touch /.dake_done

# ---- target: elixir.compile ----

FROM elixir.deps AS elixir.compile
COPY config ./config
COPY test ./test
COPY lib ./lib
COPY .*.exs ./
RUN MIX_ENV=dev mix compile --warnings-as-errors && \
    MIX_ENV=test mix compile --warnings-as-errors
RUN touch /.dake_done

# ---- target: elixir.dialyzer-plt ----

FROM elixir.deps AS elixir.dialyzer-plt
# dialyzer plt under: _build/dev/dialyxir_*.plt*
RUN mix dialyzer --plt

# ---- target: elixir.dialyzer ----

FROM elixir.compile AS elixir.dialyzer
COPY --from=elixir.dialyzer-plt /code/_build/dev/dialyxir_*.plt* ./_build/dev/
RUN mix dialyzer --no-check
RUN touch /.dake_done

# ---- target: elixir.format ----

FROM elixir.compile AS elixir.format
RUN mix format --check-formatted
RUN touch /.dake_done

# ---- target: elixir.credo ----

FROM elixir.compile AS elixir.credo
ARG ELIXIR_CREDO_OPTS="--strict --all"
RUN mix credo ${ELIXIR_CREDO_OPTS}
RUN touch /.dake_done

# ---- target: elixir.test ----

FROM elixir.compile AS elixir.test
ARG ELIXIR_TEST_CMD="coveralls.html"
RUN mix ${ELIXIR_TEST_CMD}
RUN cp -r _cover /.dake_output/
RUN touch /.dake_done

# ---- target: elixir.docs ----

FROM elixir.compile AS elixir.docs
COPY README.md ./
RUN mix docs --formatter=html
RUN cp -r doc /.dake_output/
RUN touch /.dake_done

# ---- target: elixir.release ----

FROM elixir.compile AS elixir.release
ARG ELIXIR_RELEASE_CMD="release"
RUN mix ${ELIXIR_RELEASE_CMD} --path=_release
RUN cp -r _release /.dake_output/
RUN touch /.dake_done

# ---- target: elixir.xxx-example-push ----

FROM elixir.toolchain AS elixir.xxx-example-push
RUN echo "side-effect"
RUN touch /.dake_done

# ---- target: elixir.lint ----

FROM scratch AS elixir.lint
COPY --from=elixir.dialyzer /.dake_done /.dake_done
COPY --from=elixir.format /.dake_done /.dake_done
COPY --from=elixir.credo /.dake_done /.dake_done
RUN touch /.dake_done

# ---- target: elixir.all ----

FROM scratch AS elixir.all
COPY --from=elixir.dialyzer /.dake_done /.dake_done
COPY --from=elixir.format /.dake_done /.dake_done
COPY --from=elixir.credo /.dake_done /.dake_done
COPY --from=elixir.test /code/cover /cover
COPY --from=elixir.docs /code/doc /doc
COPY --from=elixir.release /code/_release /_release
RUN touch /.dake_done

# ---- target output: elixir.test ----

FROM scratch AS elixir.test.output
COPY --from=elixir.test /.dake_output/elixir.test /

# ---- target output: elixir.docs ----

FROM scratch AS elixir.docs.output
COPY --from=elixir.docs /.dake_output/elixir.docs /

# ---- target output: elixir.release ----

FROM scratch AS elixir.release.output
COPY --from=elixir.release /.dake_output/elixir.release /