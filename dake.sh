#!/usr/bin/env sh

set -e

DAKE_IMAGE=${DAKE_IMAGE:-"dake:latest"}

if [ "$CI" = "true" ]; then
    docker run --init --rm --network=host \
        -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:$PWD" -w "$PWD" \
        -e LOG_LEVEL=${LOG_LEVEL:-notice} \
        $DAKE_IMAGE "$@"
else
    case $(uname) in
        Darwin) SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock ;;
        Linux) SSH_AUTH_SOCK="$SSH_AUTH_SOCK" ;;
    esac

    docker run --init --rm -ti --network=host \
        -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:$PWD" -w "$PWD" \
        -e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" -v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" \
        -e LOG_LEVEL=${LOG_LEVEL:-notice} \
        $DAKE_IMAGE "$@"
fi

