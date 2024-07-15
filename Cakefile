# @include git+git@github.com:visciang/cake-elixir.git#main
@include git+https://github.com/visciang/cake-elixir.git#main \
         ELIXIR_VERSION=1.17.2 \
         ELIXIR_ERLANG_VERSION=27.0.1 \
         ELIXIR_ALPINE_VERSION=3.20.1 \
         ELIXIR_ESCRIPT_EXTRA_APK="bash git openssh-client docker-cli docker-cli-buildx"

all: elixir.lint elixir.test cake.app

cake.app:
    FROM +elixir.escript
    RUN mkdir -p -m 0700 ~/.ssh \
        && ssh-keyscan github.com gitlab.com bitbucket.com >> ~/.ssh/known_hosts
