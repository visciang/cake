#!/usr/bin/env sh

set -e

DAKE_IMAGE=${DAKE_IMAGE:-"dake:latest"}


case $(uname) in
    Darwin) SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock ;;
    Linux) SSH_AUTH_SOCK="$SSH_AUTH_SOCK" ;;
esac

mkdir -p /tmp/podman/containers

podman run --privileged --init --rm -ti --network=host \
    -v "$PWD:$PWD" -w "$PWD" \
    -v /tmp/podman/containers:/var/lib/containers \
    -e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" -v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" \
    -e LOG_LEVEL=${LOG_LEVEL:-notice} \
    $DAKE_IMAGE "$@"
