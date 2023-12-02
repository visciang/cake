#!/usr/bin/env sh

set -e

# bootstrap
CAKE_VERSION=${CAKE_VERSION:-latest}
docker build --file Containerfile.bootstrap --build-arg CAKE_VERSION=${CAKE_VERSION} --target cake.app --tag cake:latest .

# cake building cake
source priv/source.sh
cake run --verbose elixir.lint
cake run --tag cake:latest cake.app
