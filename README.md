# Cake

[![.github/workflows/ci.yml](https://github.com/visciang/cake/actions/workflows/ci.yml/badge.svg)](https://github.com/visciang/cake/actions/workflows/ci.yml)

> [!WARNING]
> This is a POC, for personal use. It works on my machine!

Cake (**C**ontainerized m**AKE**) is a portable pipeline executor - a CI framework to
define and execute "reproducible" pipelines that can run on any host with docker support.

![cake](./docs/cake.png)

## Features and characteristics

- DAG pipeline definition with a Makefile / Dockerfile inspired syntax
- Parallel jobs execution
- Parametrizable pipelines and jobs (ref. `ARGS`)
- Job can be executed as a docker build or a local script
- (*) Jobs can output artifacts to the host filesystem (ref. `@output`)
- (*) Jobs can be declared as non-cacheable (ref. `@push`)
- (*) Implicit docker-like caching
- Pipelines can include pipeline templates (ref. `@include`)
- Shell integration for debug and development
- Not a Buildkit frontend

(*) docker job type only

## Install cake

### Dockerized

Cake is available as a docker image [visciang/cake](https://hub.docker.com/r/visciang/cake).

For convenience a script is provided under [priv/cake](priv/cake).
It show how to invoke the docker image with SSH forwarding, docker agent socket mount, etc.

    curl -o /usr/local/bin/cake -L https://raw.githubusercontent.com/visciang/cake/main/priv/cake
    chmod +x /usr/local/bin/cake

then edit the script to pin a cake version (`vX.Y.Z`):

    sed -i '' "s/__PLEASE_PIN_A_CAKE_VERSION_HERE__/vX.Y.Z/" /usr/local/bin/cake

### Native

You can install Cake as an elixir [escript](https://hexdocs.pm/mix/main/Mix.Tasks.Escript.Install.html):

    mix escript.install github visciang/cake tag vX.Y.Z

## A taste of cake

The following example is available in the [cake-helloworld](https://github.com/visciang/cake-helloworld) repository.
You can clone it and follow the example.

In the root of the project we have a simple example of a `Cakefile`.

```Dockerfile
ARG ALPINE_VERSION=3.19.0

devshell:
    @devshell
    FROM +toolchain

toolchain:
    FROM alpine:${ALPINE_VERSION}
    RUN apk add --no-cache gcc libc-dev

compile:
    FROM +toolchain
    COPY hello.c .
    RUN gcc hello.c -o /hello

app:
    FROM alpine:${ALPINE_VERSION}
    COPY --from=+compile /hello /usr/bin/hello
    ENTRYPOINT ["/usr/bin/hello"]
```

Cake leverage docker (without being a buildkit frontend) and the Dockerfile syntax
to define the pipeline DAG where the implicit cache semantics ihnerits the docker one.

The project source tree is:

    Cakefile
    hello.c

Let's start listing the available targets

    $ cake ls

    Global arguments:
      ALPINE_VERSION="3.19.0"

    Targets:
      app:
      compile:
      devshell:
        @devshell
      toolchain:

We can now run the pipeline to build the `app` target

    $ cake run app

    ✔  toolchain   (1.6s)
    ✔  compile   (0.3s)
    ✔  app   (0.3s)

    Run completed: ✔ 3, ✘ 0, ⏰ 0

    Elapsed 2.3s

Three targets have been built: `toolchain`, `compile` and `app` (`toolchain` is a `compile` dependency and `compile` an `app` one).

If we re-run the pipeline it will be a lot faster since it's fully cached.

To see all the logs of the pipeline you can use the `--progress plain` option

    $ cake run --progress plain app

Let's produce and tag a docker image of the `app` target:

    $ cake run --progress plain --tag hello:latest app

    +  toolchain
    ...
    ✔  toolchain   (0.2s)
    +  compile
    ...
    ✔  compile   (0.3s)
    +  app
    ...
    …  app   | #7 CACHED
    …  app   |
    …  app   | #8 exporting to image
    …  app   | #8 exporting layers done
    …  app   | #8 writing image sha256:00c838cf5b6710f1c9f7eca8e228eea53a799bd11b33a7136eec9631739e01b2 done
    …  app   | #8 naming to docker.io/library/docker:heulj4ezcomi7tpo6n5437laoq done
    …  app   | #8 naming to docker.io/library/hello:latest done
    …  app   | #8 DONE 0.0s
    …  app   |
    ✔  app   (0.2s)

    Run completed: ✔ 3, ✘ 0, ⏰ 0

    Elapsed 0.7s

The image is available in the local docker registry:

    $ docker run --rm hello:latest

    Hello Cake!

Furthermore jobs can be define as `LOCAL` jobs. These kind of jobs will be execute as local script on the running host.

```Dockerfile
ARG ALPINE_VERSION=3.19.0

hello_bash:
    LOCAL /usr/bin/env bash -c

    for idx in $(seq 10); do
      echo "Hello $idx"
    done

hello_elixir:
    LOCAL /usr/bin/env elixir -e

    for idx <- 1..10 do
      IO.puts("Hello #{idx}")
    end
```

Docker and local jobs can be mixed together in the same pipeline.

## Cakefile

Cake pipelines are defined via `Cakefile`.

The `Cakefile` of a project pipeline should sit at the root directory of the project.

### Targets

Targets in Cake represent the addressable and executable entities within a pipeline. They identify the jobs that build the Directed Acyclic Graph (DAG) of the pipeline.

A target is defined as a logical step or action within the pipeline. Each target typically corresponds to a specific task or operation to be performed. For instance, in the example Cakefile:

```Dockerfile
compile:
    FROM alpine:3.18.5
    RUN apk add --no-cache gcc libc-dev
    COPY hello.c .
    RUN gcc hello.c -o /hello

app:
    FROM alpine:3.18.5
    COPY --from=+compile /hello /usr/bin/hello
    ENTRYPOINT ["/usr/bin/hello"]
```

- `compile` and `app` are targets defined in the Cakefile.
- each target (`compile` and `app`) encompasses a series of Docker-like commands, forming the jobs required to accomplish the specified task.

### Alias Targets

An alias target defines a named set of targets that can be called via a single `run` command.

```Dockerfile
all: target_1 target_2

target_1:
    FROM alpine
    RUN echo "target 1"

target_2:
    FROM alpine
    RUN echo "target 2"
```

To run the `target_1` and `target_2` via the alias target `all`:

    $ cake run all

### Default Target

'all' is the default target that is executed if no target is provided to the run command:

    $ cake run all

### DAG

Targets collectively form the Directed Acyclic Graph (DAG) of the pipeline. The DAG represents the workflow of tasks and their dependencies, ensuring a structured execution flow without circular references.

- **Dependencies**: targets can have dependencies on other targets. For example, the `app` target depends on the successful execution of the `compile` target in the example above.

- **Execution Order**: Cake determines the execution order based on the DAG structure, ensuring that dependent targets are executed only after their dependencies successfully complete.

#### Explicit Target Dependencies

Within the Cakefile, target dependencies can be explicitly established

```Dockerfile
all: target_1 target_2

target_1:
    LOCAL /bin/sh -c
    echo "target 1"

target_2: target_1
    FROM alpine
    RUN echo "target 2"
```

In the above Cakefile `target_2` depends on `target_1` as per `target_2: target_1` definition.

Note: the alias target `all` can be thought as a special case of an empty target that explicitely depends on `target_1` and `target_2`.

#### Implicit Target Dependencies

Within the Cakefile, target dependencies are implicitly established through specific instructions within each target definition. Reference to a target are expressed conventionally with `+target`.

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
    COPY --from=+compile /hello /usr/bin/hello
    ENTRYPOINT ["/usr/bin/hello"]
  ```

  In the example above, `COPY --from=+compile /hello /usr/bin/hello` within the `app` target indicates that `app` depends on the completion of `compile`. If the `compile` target has not correctly generated the `/hello` file, the `app` target will fail during execution.

#### Dependencies and DAG Structure

Utilizing these instructions allows Cake to implicitly construct the Directed Acyclic Graph (DAG) structure of the pipeline. Each `FROM +dependency` and `COPY from=+dependency` instruction defines a dependency relationship between targets, ensuring that targets are executed in the correct order based on their dependencies.

### Caching

Cake utilizes a Dockerfile-like syntax and implicitly inherits Docker's caching semantics to optimize the pipeline execution by caching intermediate artifacts.

#### Implicit Caching

The caching mechanism in Cake relies on Docker's layer caching. When a target is executed, the docker builder checks for existing intermediate artifacts and layers cached from previous runs. If the commands and instructions in a target have not changed since the last run and the base image and dependencies remain the same, the builder uses the cached layers instead of rebuilding the entire target. This significantly speeds up subsequent executions of the pipeline.

#### Cache Invalidation

Cake invalidates the cache for a specific target if any of the following occurs:

- Changes are made to the target's instructions or commands.
- The base image or dependencies specified in the FROM instruction are updated.
- Any dependency used in a target has altered outputs since the last build.

#### Leverage for Faster Builds

By leveraging Docker's caching mechanisms, the docker builder optimizes build times by avoiding redundant execution of unchanged commands or layers, ensuring that only modified parts of the pipeline are rebuilt. This behavior effectively enhances productivity and speeds up the development and deployment cycles.

### Pipeline Parametrization

Cake supports parameterization to enhance the flexibility and reusability of pipelines. Parameters enable the customization of pipeline behavior and settings without altering the pipeline structure itself.

#### Using Parameters

Parameters in Cake are defined using the `ARG` keyword within the Cakefile. These parameters can be set with default values or overridden when executing the pipeline.

Parameters in Cake can be either global or local to specific targets, providing granular control over their scope and applicability within the pipeline.

By convention `ARG` starting with an `_` character can be used to identify non public arguments.

##### Global Parameters

Global parameters, declared at the top of the Cakefile using the ARG keyword, are accessible throughout the entire pipeline, allowing for consistent values across multiple targets.

```Dockerfile
ARG ALPINE_VERSION=3.14.5
```

##### Local Parameters

Local parameters are defined within individual targets and are specific to those targets. They enable customization on a per-target basis, allowing for different values to be used within separate parts of the pipeline.

```Dockerfile
target:
    ARG SOME_PARAMETER=default_value
    # Target-specific instructions using SOME_PARAMETER
```

#### Overriding Parameters

When running the pipeline, parameters can be overridden via the command line, allowing for dynamic configurations.

Command line override:

```
cake run app ALPINE_VERSION=3.15.2
```

Parameters override can be defined also on `@include` directives.

#### Enhancing Flexibility

Parameterization enables the creation of versatile pipelines that can adapt to different environments, requirements, or specific use cases by adjusting values without modifying the underlying pipeline structure. This capability fosters easier management and deployment of pipelines across various scenarios.

The distinction between global and local parameters grants flexibility in managing values across the pipeline. Global parameters offer consistency and ease of management across multiple targets, while local parameters provide targeted customization for specific parts of the pipeline.

### Directives

Directives in Cake are declarations that enforce the underlying Docker-like semantics, enhancing pipeline integration within CI while promoting composability and reusability.

The conventions for directives follow the format `@directive_name`.

#### Output

Format: `@output <dir>`

Used to output artifacts from a docker target to the host filesystem.

Example:

```Dockerfile
test:
    @output /outputs/coverage
    FROM +compile
    # run test with coverage (output to /outputs/coverage)
```

Note: output take effect only if the run command includes the `--output` flag.

#### Push

Format: `@push`

Identifies non-cacheable docker targets, primarily used for side-effects (e.g. deployments).

Note: push targets can only be executed if the run commands include the `--push` flag

#### Include

`@include <ref> [<arg>, ...]`

Includes an external Cakefile "template". The directive should be defined before any target.

The reference to the Cakefile can be a:
- local path: `./local_dir`
- remote Git URL (via HTTPS): `git+https://github.com/username/repository.git#ref_branch_or_tag`
- remote Git URL (via SSH): `git+git@github.com/username/repository.git#ref_branch_or_tag`

A subdirectory where the Cakefile include is located can be defined with:

`git+https://github.com/username/repository.git/subdirs#ref_branch_or_tag`

If the included Cakefile has parameter they can be specified via args

Example:

```Dockerfile
@include git+https://github.com/visciang/cake-elixir.git#main \
         ELIXIR_ESCRIPT_EXTRA_APK="bash git"
```

#### Development Shell

`@devshell`

Tag the docker target as a "devshell" - a docker target that can be used a development container.

Equivalent to `cake run --shell <devshell target>`.

The `--shell` option instruct Cake to bind mount the project code into the container when a shell is requested.

```Dockerfile
elixir.toolchain:
    @devshell
    FROM +elixir.base
    RUN apk add --no-cache git build-base
    # ...
```

Attach to a dev shell:

    $ cake devshell

    # equivalent to

    $ cake run --shell elixir.toolchain

### Integration tests

TODO

## Commands

The cake CLI commands.

### LS

List targets.

The output includes details about:

- Arguments and their default value (ref [ARG](#pipeline-parametrization))
- [@output](#output)
- [@devshell](#development-shell)

```
$ cake ls

Global arguments:
  ELIXIR_ESCRIPT_EXTRA_APK="bash git openssh-client docker-cli docker-cli-buildx"

Aliases:
  all: elixir.lint elixir.test cake.app
  elixir.lint: elixir.dialyzer elixir.format elixir.credo

Targets:
  cake.app:
  elixir.base:
  elixir.compile:
  elixir.credo:
    ELIXIR_CREDO_OPTS="--strict --all"
  elixir.deps:
  elixir.dialyzer:
  elixir.dialyzer-plt:
  elixir.docs:
    @output /code/doc
  elixir.escript:
    ELIXIR_ESCRIPT_EXTRA_APK
  elixir.escript-build:
  elixir.format:
  elixir.release:
  elixir.test:
    @output /code/cover
    ELIXIR_TEST_CMD="coveralls.html"
  elixir.toolchain:
    @devshell
```

### RUN

Run the pipeline.

#### output artifacts
TODO

#### entering a debug/dev shell
TODO

#### taggin a docker image
TODO

#### push targets
TODO
