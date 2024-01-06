#!/usr/bin/env sh

set -e

# bootstrap
docker build --file Dockerfile --target cake.app --tag visciang/cake:latest .

# cake building cake
priv/cake run --progress plain all
priv/cake run --tag cake:latest cake.app
