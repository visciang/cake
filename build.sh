#!/usr/bin/env sh

set -e

# bootstrap
docker build --file Dockerfile --target cake.app --tag cake:latest .

# cake building cake
priv/cake run --verbose all
priv/cake run --tag cake:latest cake.app
