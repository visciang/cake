#!/usr/bin/env sh

set -ex

DAKE_IMAGE=${DAKE_IMAGE:-"dake:latest"}

case $(uname) in
    Darwin) SSH_AUTH_SOCK=/run/host-services/ssh-auth.sock ;;
    Linux) SSH_AUTH_SOCK="$SSH_AUTH_SOCK" ;;
esac

if [ "$CI" == "true" ]; then
    OPTS=""
else
    OPTS="-ti"
fi

docker run $OPTS --init --rm --network=host \
    -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:$PWD" -w "$PWD" \
    -e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" -v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" \
    -e LOG_LEVEL=${LOG_LEVEL:-notice} \
    $DAKE_IMAGE "$@"
