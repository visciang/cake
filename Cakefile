# @include git+git@github.com:visciang/cake-elixir.git#main ELIXIR_ESCRIPT_EXTRA_APK="bash git openssh-client docker-cli-buildx graphviz"
@include git+https://github.com/visciang/cake-elixir.git#main ELIXIR_ESCRIPT_EXTRA_APK="bash git openssh-client docker-cli-buildx graphviz"

cake.app:
    FROM +elixir.escript
    RUN mkdir -p -m 0700 ~/.ssh \
        && ssh-keyscan github.com gitlab.com bitbucket.com >> ~/.ssh/known_hosts
    COPY priv/cake_cmd.sh /usr/bin/
