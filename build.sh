#!/usr/bin/env sh

set -e

VERSION=$(grep -oE 'version: ("[0-9]+\.[0-9]+\.[0-9]+")' mix.exs | cut -d '"' -f 2)

docker buildx build --file Dockerfile.bootstrap --target dake.app --tag dake:latest .

DOCKER_RUN="docker run --init --rm -ti -v /var/run/docker.sock:/var/run/docker.sock -v '$PWD:$PWD' -w '$PWD'"
eval "$DOCKER_RUN dake:latest run elixir.lint"
eval "$DOCKER_RUN dake:latest run --tag dake:$VERSION dake.app"
eval "$DOCKER_RUN dake:$VERSION run --tag dake:latest dake.app"
