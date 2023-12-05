# Cake

Cake (**C**ontainerized m**AKE**) is a portable pipeline executor - a CI/CD framework to
define and execute "reproducible" pipelines that can run on any host with docker support.

![dalle](./docs/cake.png)

## Features and characteristics

- DAG pipeline definition with a Dockerfile-like syntax
- Implicit docker-like caching
- Parallel jobs execution
- Parametrizable pipeline and job (ref. `ARGS`)
- Jobs can output artifacts to the host filesystem (ref. `@output`)
- Jobs can be declared as non-cacheable (ref. `@push`)
- Pipelines can include pipeline templates (ref. `@include`)
- Jobs can import external pipeline targets (ref. `@import`)
- Shell integration for debug and development

## A taste of cake

The following is a simple example of a `Cakefile`.

```Dockerfile
ARG ALPINE_VERSION=3.18.5

build:
    FROM alpine:${ALPINE_VERSION}
    RUN apk add --no-cache gcc libc-dev
    COPY hello.c .
    RUN gcc hello.c -o /hello

app:
    FROM alpine:${ALPINE_VERSION}
    COPY --from=+build /hello /usr/bin/hello
    ENTRYPOINT ["/usr/bin/hello"]
```

The target declaration feels like `make` and their definition feels like a `Dockerfile`.

In fact `cake` Cake leverage docker (without being a buildkit frontend) and the Dockerfile syntax
to define the pipeline DAG where the implicit cache semantics ihnerits the docker one.

The project source tree is:

    Cakefile
    hello.c

Let's start to list the available targets

    $ cake ls

    [!]  ls   |
    [!]  ls   | Global arguments:
    [!]  ls   |  - ALPINE_VERSION="3.18.5"
    [!]  ls   |
    [!]  ls   | Targets (with arguments):
    [!]  ls   |  - build
    [!]  ls   |  - app

We can now run the pipeline to build the `app` target

    $ cake run app

    [+]  build
    [✔]  build   (10.542 s)
    [+]  app
    [✔]  app   (1.285 s)

    Completed (2 jobs) (11.973 s)

if we re-run the pipeline it will be a lot faster since it's fully cached.

To see all the logs of the pipeline you can use the `--verbose` option

    $ cake run --verbose app

Let's produce and tag a docker image of the `app` target:

    $ cake run --verbose --tag hello:latest app

    [+]  build
    ...
    [✔]  build   (0.323 s)
    [+]  app
    ...
    [.]  app   | #7 CACHED
    [.]  app   |
    [.]  app   | #8 exporting to image
    [.]  app   | #8 exporting layers done
    [.]  app   | #8 writing image sha256:00c838cf5b6710f1c9f7eca8e228eea53a799bd11b33a7136eec9631739e01b2 done
    [.]  app   | #8 naming to docker.io/library/docker:heulj4ezcomi7tpo6n5437laoq done
    [.]  app   | #8 naming to docker.io/library/hello done
    [.]  app   | #8 DONE 0.0s
    [.]  app   |
    [✔]  app   (0.282 s)

    Completed (2 jobs) (0.737 s)

The image is available in the local docker registry:

    $ docker run --rm hello:latest
    
    Hello!

## Cakefile reference
### Targets
### DAG
### Caching
### Parametrization
### Directives
#### Output
#### Push
#### Include
#### Import
### Aliases
### Integration tests

## Install cake
### Native
### Dockerized
### Shell aliases

- Fish: `./priv/source.fish`
- Sh: `./priv/source.sh`
