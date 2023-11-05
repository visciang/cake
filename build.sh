#!/usr/bin/env sh

set -e

VERSION=$(grep -oE 'version: ("[0-9]+\.[0-9]+\.[0-9]+")' mix.exs | cut -d '"' -f 2)

docker build --ssh=default --file Dockerfile.bootstrap --target dake.app --tag dake:latest .

# eval "DAKE_IMAGE="dake:latest" ./dake.sh run elixir.lint"
# eval "DAKE_IMAGE="dake:latest" ./dake.sh run --tag dake:$VERSION dake.app"
# eval "DAKE_IMAGE="dake:$VERSION" ./dake.sh run --tag dake:latest dake.app"
