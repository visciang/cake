# Cake

Cake (**C**ontainerized m**AKE**) is a portable pipeline executor - a CI/CD framework to
define and execute "reproducible" pipelines that can run on any host with docker support.

![dalle](./docs/cake.png)

## Features and characteristics

- DAG pipeline definition with a Dockerfile-like syntax
- Not a Buildkit frontend
- Implicit docker-like caching
- Parallel jobs execution
- Parametrizable pipelines and jobs (ref. `ARGS`)
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

    ✔  build   (10.5s)
    ✔  app   (1.2s)

    Completed (2 jobs) (11.9s)

if we re-run the pipeline it will be a lot faster since it's fully cached.

To see all the logs of the pipeline you can use the `--progress plain` option

    $ cake run --progress plain app

Let's produce and tag a docker image of the `app` target:

    $ cake run --progress plain --tag hello:latest app

    +  build
    ...
    ✔  build   (0.3s)
    +  app
    ...
    …  app   | #7 CACHED
    …  app   |
    …  app   | #8 exporting to image
    …  app   | #8 exporting layers done
    …  app   | #8 writing image sha256:00c838cf5b6710f1c9f7eca8e228eea53a799bd11b33a7136eec9631739e01b2 done
    …  app   | #8 naming to docker.io/library/docker:heulj4ezcomi7tpo6n5437laoq done
    …  app   | #8 naming to docker.io/library/hello done
    …  app   | #8 DONE 0.0s
    …  app   |
    ✔  app   (0.2s)

    Completed (2 jobs) (0.7s)

The image is available in the local docker registry:

    $ docker run --rm hello:latest

    Hello!

## Cakefile

Cake pipelines are defined via `Cakefile`.

The `Cakefile` of a project pipeline should sit at the root directory of the project.

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
    COPY --from=+build /hello /usr/bin/hello
    ENTRYPOINT ["/usr/bin/hello"]
  ```

  In the example above, `COPY --from=+build /hello /usr/bin/hello` within the `app` target indicates that `app` depends on the completion of `build`. If the `build` target has not correctly generated the `/hello` file, the `app` target will fail during execution.

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

```bash
cake run --build-arg ALPINE_VERSION=3.15.2 app
```

#### Enhancing Flexibility

Parameterization enables the creation of versatile pipelines that can adapt to different environments, requirements, or specific use cases by adjusting values without modifying the underlying pipeline structure. This capability fosters easier management and deployment of pipelines across various scenarios.

The distinction between global and local parameters grants flexibility in managing values across the pipeline. Global parameters offer consistency and ease of management across multiple targets, while local parameters provide targeted customization for specific parts of the pipeline.

### Directives

Directives in Cake are declarations that enforce the underlying Docker-like semantics, enhancing pipeline integration within CI while promoting composability and reusability.

The conventions for directives follow the format `@directive_name`.

#### Output

Format: `@output <dir>`

Used to output artifacts from a target to the host filesystem.

Example:

```Dockerfile
test:
    @output ./coverage
    FROM +compile
    # RUN test with coverage
```

Note: output take effect only if the run command includes the `--output` flag.

#### Push

Format: `@push`

Identifies non-cacheable targets, primarily used for side-effects (e.g. deployments).

Note: push targets can only be executed if the run commands include the `--push` flag

#### Include

`@include <ref> [<arg>, ...]`

Includes an external Cakefile "template". The directive should be defined before any target.

The reference to the Cakefile can be a local path (`./local_dir`) or a remote Git URL (`git+https://github.com/username/cake-template.git#main` or `git+git@github.com:visciang/cake-elixir.git#1.0.0`).

If the included Cakefile has parameter they can be specified via args

Example:

```Dockerfile
@include git+https://github.com/visciang/cake-elixir.git#main \
         ELIXIR_ESCRIPT_EXTRA_APK="bash git"
```

#### Import

`@import [--ouput] [--push] --as=<as> <ref> <target> [<arg>, ...]`

Imports a remote `<target>` from `<ref>`, building the referenced target and making it available in the current target scope with the `<as>` identifier.

```Dockerfile
app:
    @import --as=imported_target components/app_ta app
    FROM imported_target:${CAKE_PIPELINE_UUID}
    # ...
```

### Aliases
### Integration tests

## Install cake
### Native
### Dockerized
