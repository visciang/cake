#!/usr/bin/env sh

set -e

DAKE_VERSION=${DAKE_VERSION:-latest}

docker build --ssh=default --file Dockerfile.bootstrap --build-arg DAKE_VERSION=${DAKE_VERSION} --target dake.app --tag dake:latest .

./dake.sh run --verbose elixir.lint
./dake.sh run --tag dake:latest dake.app
