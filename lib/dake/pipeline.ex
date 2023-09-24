defmodule Dake.Pipeline.Error do
  defexception [:message]
end

defmodule Dake.Pipeline do
  alias Dake.Cli.Run
  alias Dake.Parser.{Dakefile, Directive, Docker, Target}
  alias Dake.Pipeline.Docker, as: DockerCmd
  alias Dake.{Dag, Dir, Reporter, Type}

  require Logger
  require Dake.Reporter.Status

  @spec build(Run.t(), Dakefile.t(), Dag.graph()) :: Dask.t()
  def build(%Run{} = run, %Dakefile{} = dakefile, graph) do
    pipeline_uuid = pipeline_uuid()

    Logger.info("#{inspect(dakefile.path)}", pipeline: pipeline_uuid)

    dakefile = fq_targets_image_ref(pipeline_uuid, dakefile)
    targets_map = Map.new(dakefile.targets, &{&1.tgid, &1})
    pipeline_tgids = Dag.reaching_tgids(graph, run.tgid)

    validate_cmd(run, Map.fetch!(targets_map, run.tgid))

    copy_includes_ctx(dakefile, pipeline_uuid)

    pipeline_tgids =
      if run.push do
        pipeline_tgids
      else
        Enum.reject(pipeline_tgids, &push_target?(targets_map[&1]))
      end

    dask =
      Enum.reduce(pipeline_tgids, Dask.new(), fn tgid, dask ->
        target = Map.fetch!(targets_map, tgid)
        build_dask_job(run, dakefile, dask, tgid, target, pipeline_uuid)
      end)

    dask =
      Enum.reduce(pipeline_tgids, dask, fn tgid, dask ->
        upstream_tgids = Dag.upstream_tgids(graph, tgid)
        Dask.flow(dask, upstream_tgids, tgid)
      end)

    dask = build_dask_job_cleanup(dask, :cleanup, pipeline_uuid)
    Dask.flow(dask, run.tgid, :cleanup)
  end

  @spec build_dask_job(Run.t(), Dakefile.t(), Dask.t(), Type.tgid(), Dakefile.target(), Type.pipeline_uuid()) ::
          Dask.t()
  defp build_dask_job(%Run{} = run, %Dakefile{} = dakefile, dask, tgid, target, pipeline_uuid) do
    job_fn = fn ^tgid, _upstream_jobs_status ->
      Reporter.job_start(run.ns, tgid)

      case target do
        %Target.Alias{} ->
          :ok

        %Target.Docker{} = docker ->
          dask_job_docker(run, dakefile, docker, tgid, pipeline_uuid)
      end

      :ok
    end

    job_on_exit_fn = fn ^tgid, _upstream_results, job_exec_result ->
      case job_exec_result do
        {:job_ok, :ok} ->
          Reporter.job_end(run.ns, tgid, Reporter.Status.ok())

        :job_timeout ->
          Reporter.job_end(run.ns, tgid, Reporter.Status.timeout())

        {:job_error, %Dake.Pipeline.Error{} = err, _stacktrace} ->
          Reporter.job_end(run.ns, tgid, Reporter.Status.error(err.message, nil))

        {:job_error, reason, stacktrace} ->
          Reporter.job_end(run.ns, tgid, Reporter.Status.error(reason, stacktrace))

        :job_skipped ->
          :ok
      end
    end

    Dask.job(dask, tgid, job_fn, :infinity, job_on_exit_fn)
  end

  @spec dask_job_docker(Run.t(), Dakefile.t(), Target.Docker.t(), Type.tgid(), Type.pipeline_uuid()) :: :ok
  defp dask_job_docker(%Run{} = run, %Dakefile{} = dakefile, %Target.Docker{} = docker, tgid, pipeline_uuid) do
    Logger.info("start for #{inspect(tgid)}", pipeline: pipeline_uuid)

    dask_job_docker_imports(run, docker, pipeline_uuid)

    job_uuid = to_string(System.unique_integer([:positive]))
    docker_build_ctx_dir = Path.dirname(dakefile.path)

    build_relative_include_ctx_dir =
      if docker.included_from_ref do
        include_ctx_dir = local_include_ctx_dir(dakefile, docker.included_from_ref)
        Path.relative_to(include_ctx_dir, docker_build_ctx_dir)
      else
        ""
      end

    dakefile = insert_builtin_global_args(dakefile, pipeline_uuid)
    docker = insert_builtin_docker_args(docker, build_relative_include_ctx_dir)

    dockerfile_path = Path.join(Dir.tmp(), "#{job_uuid}-#{tgid}.Dockerfile")
    write_dockerfile(dakefile.args, docker, dockerfile_path)

    args = docker_build_cmd_args(run, dockerfile_path, tgid, pipeline_uuid, docker_build_ctx_dir)
    DockerCmd.docker_build(run, tgid, args, pipeline_uuid)

    if run.shell and tgid == run.tgid do
      IO.puts("\nStarting interactive shell in #{run.tgid}:\n")

      DockerCmd.docker_shell(tgid, pipeline_uuid)
    end

    if run.output do
      outputs =
        docker.directives
        |> Enum.filter(&match?(%Directive.Output{}, &1))
        |> Enum.map(& &1.dir)

      DockerCmd.docker_output(run, tgid, pipeline_uuid, outputs)
    end

    :ok
  end

  @spec dask_job_docker_imports(Run.t(), Target.Docker.t(), Type.pipeline_uuid()) :: :ok
  defp dask_job_docker_imports(%Run{} = run, %Target.Docker{} = docker, pipeline_uuid) do
    docker.directives
    |> Enum.filter(&match?(%Directive.Import{}, &1))
    |> Enum.each(fn %Directive.Import{} = import_ ->
      unless File.exists?(import_.ref) do
        raise Dake.Pipeline.Error, "cannot @import #{inspect(import_.ref)}"
      end

      Logger.info("running pipeline for imported target #{inspect(import_.target)} dakefile=#{inspect(import_.ref)}",
        pipeline: pipeline_uuid
      )

      cmd_res =
        Dake.cmd(
          %Run{
            ns: run.ns ++ [docker.tgid],
            tgid: import_.target,
            args: Enum.map(import_.args, &{&1.name, &1.default_value}),
            push: import_.push and run.push,
            output: import_.output and run.output,
            output_dir: import_.as,
            tag: DockerCmd.fq_image(import_.as, pipeline_uuid),
            timeout: :infinity,
            parallelism: run.parallelism,
            verbose: run.verbose,
            save_logs: run.save_logs,
            shell: false
          },
          Path.dirname(import_.ref)
        )

      case cmd_res do
        :ok -> :ok
        {:error, _} -> raise Dake.Pipeline.Error, "failed @import #{inspect(import_.ref)} build"
        :timeout -> raise Dake.Pipeline.Error, "timeout"
      end
    end)
  end

  @spec build_dask_job_cleanup(Dask.t(), Dask.Job.id(), Type.pipeline_uuid()) :: Dask.t()
  defp build_dask_job_cleanup(dask, cleanup_job_id, pipeline_uuid) do
    job_passthrough_fn = fn _, _ ->
      :ok
    end

    job_on_exit_fn = fn _, _, _ ->
      DockerCmd.docker_cleanup(pipeline_uuid)
    end

    Dask.job(dask, cleanup_job_id, job_passthrough_fn, :infinity, job_on_exit_fn)
  end

  @spec docker_build_cmd_args(Run.t(), Path.t(), Type.tgid(), Type.pipeline_uuid(), Path.t()) :: [String.t()]
  defp docker_build_cmd_args(%Run{} = run, dockerfile_path, tgid, pipeline_uuid, build_ctx) do
    Enum.concat([
      ["--progress", "plain"],
      ["--file", dockerfile_path],
      ["--tag", DockerCmd.fq_image(tgid, pipeline_uuid)],
      if(tgid == run.tgid and run.tag, do: ["--tag", run.tag], else: []),
      Enum.flat_map(run.args, fn {name, value} -> ["--build-arg", "#{name}=#{value}"] end),
      [build_ctx]
    ])
  end

  @spec push_target?(Dakefile.target()) :: boolean()
  defp push_target?(%Target.Alias{}), do: false

  defp push_target?(%Target.Docker{} = docker) do
    Enum.any?(docker.directives, &match?(%Directive.Push{}, &1))
  end

  @spec validate_cmd(Run.t(), Dakefile.target()) :: :ok | no_return()
  defp validate_cmd(%Run{} = run, target) do
    if run.push and push_target?(target) do
      Dake.System.halt(:error, "@push target #{run.tgid} can be executed only via 'run --push'")
    end

    if run.shell and match?(%Target.Alias{}, target) do
      Dake.System.halt(:error, "cannot shell into and \"alias\" target")
    end

    :ok
  end

  @spec insert_builtin_global_args(Dakefile.t(), Type.pipeline_uuid()) :: Dakefile.t()
  defp insert_builtin_global_args(%Dakefile{} = dakefile, pipeline_uuid) do
    %Dakefile{
      dakefile
      | args: dakefile.args ++ [%Docker.Arg{name: "DAKE_PIPELINE_UUID", default_value: pipeline_uuid}]
    }
  end

  @spec insert_builtin_docker_args(Target.Docker.t(), Path.t()) :: Target.Docker.t()
  defp insert_builtin_docker_args(%Target.Docker{} = docker, include_ctx_dir) do
    from_idx = Enum.find_index(docker.commands, &match?(%Docker.From{}, &1))
    {pre_from_cmds, [%Docker.From{} = from | post_from_cmds]} = Enum.split(docker.commands, from_idx)

    commands =
      pre_from_cmds ++
        [from, %Docker.Arg{name: "DAKE_INCLUDE_CTX", default_value: include_ctx_dir}] ++ post_from_cmds

    %Target.Docker{docker | commands: commands}
  end

  @spec copy_includes_ctx(Dakefile.t(), Type.pipeline_uuid()) :: :ok
  defp copy_includes_ctx(%Dakefile{} = dakefile, pipeline_uuid) do
    dakefile.targets
    |> Enum.filter(&match?(%Target.Docker{included_from_ref: inc} when inc != nil, &1))
    |> List.flatten()
    |> Enum.each(fn %Target.Docker{included_from_ref: included_from_ref} ->
      include_ctx_dir = Path.join(Path.dirname(included_from_ref), "ctx")

      if File.exists?(include_ctx_dir) do
        dest = local_include_ctx_dir(dakefile, included_from_ref)

        Logger.info("from #{inspect(included_from_ref)}", pipeline: pipeline_uuid)

        File.rm_rf!(dest)
        File.mkdir_p!(dest)
        File.cp_r!(include_ctx_dir, dest)
      end
    end)
  end

  @spec local_include_ctx_dir(Dakefile.t(), String.t()) :: Path.t()
  defp local_include_ctx_dir(%Dakefile{} = dakefile, include_ref) do
    dakefile_dir = Path.dirname(dakefile.path)
    include_ref_dir = Path.dirname(include_ref)
    include_ctx_dir = Dir.include_ctx(dakefile_dir)
    Path.join(include_ctx_dir, include_ref_dir)
  end

  @spec write_dockerfile([Docker.Arg.t()], Target.Docker.t(), Path.t()) :: :ok
  defp write_dockerfile(args, %Target.Docker{} = docker, path) do
    dockerfile = Enum.map_join(args ++ docker.commands, "\n", &Docker.Fmt.fmt(&1))
    File.write!(path, dockerfile)

    :ok
  end

  @spec fq_targets_image_ref(Type.pipeline_uuid(), Dakefile.t()) :: Dakefile.t()
  defp fq_targets_image_ref(pipeline_uuid, %Dakefile{} = dakefile) do
    update_fn = fn "+" <> tgid -> DockerCmd.fq_image(tgid, pipeline_uuid) end

    dakefile =
      update_in(
        dakefile,
        [
          Access.key!(:targets),
          Access.filter(&match?(%Target.Docker{}, &1)),
          Access.key!(:commands),
          Access.filter(&match?(%Docker.From{image: "+" <> _}, &1)),
          Access.key!(:image)
        ],
        update_fn
      )

    update_in(
      dakefile,
      [
        Access.key!(:targets),
        Access.filter(&match?(%Target.Docker{}, &1)),
        Access.key!(:commands),
        Access.filter(&match?(%Docker.Command{instruction: "COPY"}, &1)),
        Access.key!(:options),
        Access.filter(&match?(%Docker.Command.Option{name: "from"}, &1)),
        Access.key!(:value)
      ],
      update_fn
    )
  end

  @spec pipeline_uuid :: Type.pipeline_uuid()
  defp pipeline_uuid do
    Base.encode32(:crypto.strong_rand_bytes(16), case: :lower, padding: false)
  end
end
