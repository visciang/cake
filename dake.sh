#!/usr/bin/env sh

set -e

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
DAKE_IMAGE=${DAKE_IMAGE:-"dake:latest"}
PODMAN_CONTAINERS_CACHE="$SCRIPT_DIR/.dake/podman/containers"

mkdir -p "$PODMAN_CONTAINERS_CACHE"

case $(uname) in
    Darwin) SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock ;;
    Linux) SSH_AUTH_SOCK="$SSH_AUTH_SOCK" ;;
esac

podman run --privileged --init --rm -ti \
    -v "$PWD:$PWD" -w "$PWD" \
    -v "$PODMAN_CONTAINERS_CACHE:/var/lib/containers" \
    -e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" -v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" \
    -e LOG_LEVEL=${LOG_LEVEL:-notice} \
    $DAKE_IMAGE "$@"
