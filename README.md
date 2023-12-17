# Cake

Cake (**C**ontainerized m**AKE**) is a portable pipeline executor - a CI/CD framework to
define and execute "reproducible" pipelines that can run on any host with docker support.

![dalle](./docs/cake.png)

## Features and characteristics

- DAG pipeline definition with a Dockerfile-like syntax
- Buildkit free (it is not a buildkit frontend)
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

     Global arguments:
      - ALPINE_VERSION="3.18.5"

     Targets:
      - build
      - app

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

Targets in Cake represent the addressable and executable entities within a pipeline. They identify the jobs that build the Directed Acyclic Graph (DAG) of the pipeline.

A target is defined as a logical step or action within the pipeline. Each target can encapsulate one or more jobs and typically corresponds to a specific task or operation to be performed. For instance, in the example Cakefile:

```Dockerfile
build:
    FROM alpine:3.18.5
    RUN apk add --no-cache gcc libc-dev
    COPY hello.c .
    RUN gcc hello.c -o /hello

app:
    FROM alpine:3.18.5
    COPY --from=+build /hello /usr/bin/hello
    ENTRYPOINT ["/usr/bin/hello"]
```

- `build` and `app` are targets defined in the Cakefile.
- each target (`build` and `app`) encompasses a series of Docker-like commands, forming the jobs required to accomplish the specified task.

### DAG

Targets collectively form the Directed Acyclic Graph (DAG) of the pipeline. The DAG represents the workflow of tasks and their dependencies, ensuring a structured execution flow without circular references.

- **Dependencies**: targets can have dependencies on other targets. For example, the app target depends on the successful execution of the build target in the example above.

- **Execution Order**: Cake determines the execution order based on the DAG structure, ensuring that dependent targets are executed only after their dependencies successfully complete.

#### Implicit Target Dependencies

Within the Cakefile, target dependencies are implicitly established through specific instructions within each target definition.

Reference to a target are expressed conventionally with `+target`.

- `FROM +dependency` instruction

  The `FROM +dependency` instruction within a target denotes a direct dependency on another previously defined target. When a target specifies a base image using this syntax, it creates a dependency on a target labeled as `dependency`.

  For instance:

  ```Dockerfile
  toolchain:
    FROM alpine:3.18.5
    # ...

  compile:
      FROM +toolchain
      # ...

  test:
      FROM +compile
      # ...
  ```

  In the above example `test` depends on `compile` and `compile` on `toolchain`.

- `COPY from=+dependency` instruction

  The `COPY from=+dependency` instruction is used to copy specific files or artifacts produced by a previously executed target. This instruction creates a direct dependency on the target labeled as `dependency`, as it must complete successfully for the `COPY` instruction to operate correctly.

  ```Dockerfile
  app:
    FROM alpine:3.18.5
    COPY --from=+build /hello /usr/bin/hello
    ENTRYPOINT ["/usr/bin/hello"]
  ```

  In the example above, `COPY --from=+build /hello /usr/bin/hello` within the `app` target indicates that `app` depends on the completion of `build`. If the `build` target has not correctly generated the `/hello` file, the `app` target will fail during execution.

#### Dependencies and DAG Structure

Utilizing these instructions allows Cake to implicitly construct the Directed Acyclic Graph (DAG) structure of the pipeline. Each `FROM +dependency` and `COPY from=+dependency` instruction defines a dependency relationship between targets, ensuring that targets are executed in the correct order based on their dependencies.

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
