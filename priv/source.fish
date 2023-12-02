function cake
    if not set -q CAKE_IMAGE
        set CAKE_IMAGE "cake:latest"
    end

    if not set -q LOG_LEVEL
        set LOG_LEVEL "notice"
    end

    if test (uname) = "Darwin"
        set SSH_AUTH_SOCK "/run/host-services/ssh-auth.sock"
    end

    if test "$CI" = "true"
        set TI ""
    else
        set TI "-ti"
    end

    docker run --init --rm $TI --network=host \
        -v /var/run/docker.sock:/var/run/docker.sock -v "$PWD:$PWD" -w "$PWD" \
        -e SSH_AUTH_SOCK="$SSH_AUTH_SOCK" -v "$SSH_AUTH_SOCK:$SSH_AUTH_SOCK" \
        -e LOG_LEVEL="$LOG_LEVEL" \
        $CAKE_IMAGE $argv
end
