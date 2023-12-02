function cake {
    CAKE_IMAGE=${CAKE_IMAGE:-"cake:latest"}

    if [ "$(uname)" == "Darwin" ]; then
        SSH_AUTH_SOCK="/run/host-services/ssh-auth.sock"
    fi

    docker run --init --rm -ti --network=host \
        -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:$PWD" -w "$PWD" \
        -e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" -v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" \
        -e LOG_LEVEL="${LOG_LEVEL:-notice}" \
        $CAKE_IMAGE "$@"
}
