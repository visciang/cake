#!/usr/bin/env sh

set -e

VERSION=$(grep -oE 'version: ("[0-9]+\.[0-9]+\.[0-9]+")' mix.exs | cut -d '"' -f 2)

docker buildx build --file Dockerfile.bootstrap --target app --tag dake:latest .
docker run --rm -ti -v /var/run/docker.sock:/var/run/docker.sock -v $PWD:$PWD -w $PWD dake:latest run elixir.lint
docker run --rm -ti -v /var/run/docker.sock:/var/run/docker.sock -v $PWD:$PWD -w $PWD dake:latest run --tag "dake:$VERSION" elixir.escript
docker run --rm -ti -v /var/run/docker.sock:/var/run/docker.sock -v $PWD:$PWD -w $PWD dake:$VERSION run --tag "dake:latest" elixir.escript
