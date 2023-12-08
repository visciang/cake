#!/usr/bin/env sh

set -e

# bootstrap
CAKE_VERSION=${CAKE_VERSION:-0.0.0}
docker build --file Containerfile --build-arg CAKE_VERSION=${CAKE_VERSION} --target cake.app --tag cake:latest .

# cake building cake
source priv/source.sh
cake run --verbose all
cake run --tag cake:latest cake.app
