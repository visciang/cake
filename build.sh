#!/usr/bin/env sh

set -e

CAKE_VERSION=${CAKE_VERSION:-latest}

docker build --ssh=default --file Containerfile.bootstrap --build-arg CAKE_VERSION=${CAKE_VERSION} --target cake.app --tag cake:latest .

./cake.sh run --verbose elixir.lint
./cake.sh run --tag cake:latest cake.app
