#!/usr/bin/env sh

set -e

docker run --init --rm -ti -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:$PWD" -w "$PWD" dake:latest "$@"