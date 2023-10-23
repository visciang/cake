defmodule Dake.Pipeline.Error do
  defexception [:message]
end

defmodule Dake.Pipeline do
  alias Dake.Cli.Run
  alias Dake.Parser.{Dakefile, Directive, Docker, Target}
  alias Dake.{Dag, Dir, Reporter, Type}

  require Dake.Reporter.Status

  @typep pipeline_uuid :: String.t()

  @spec build(Run.t(), Dakefile.t(), Dag.graph()) :: Dask.t()
  def build(%Run{} = run, %Dakefile{} = dakefile, graph) do
    pipeline_uuid = pipeline_uuid()
    dakefile = fq_targets_image_ref(pipeline_uuid, dakefile)
    targets_map = Map.new(dakefile.targets, &{&1.tgid, &1})
    pipeline_tgids = Dag.reaching_tgids(graph, run.tgid)

    validate_cmd(run, Map.fetch!(targets_map, run.tgid))

    copy_includes_ctx(dakefile)

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

  @spec build_dask_job(Run.t(), Dakefile.t(), Dask.t(), Type.tgid(), Dakefile.target(), pipeline_uuid()) :: Dask.t()
  defp build_dask_job(%Run{} = run, %Dakefile{} = dakefile, dask, tgid, target, pipeline_uuid) do
    job_fn = fn ^tgid, _upstream_jobs_status ->
      Reporter.job_start(run.ns, tgid)

      case target do
        %Target.Alias{} ->
          :ok

        %Target.Docker{} = docker ->
          build_dask_job_docker(run, dakefile, docker, tgid, pipeline_uuid)
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

  @spec build_dask_job_docker(Run.t(), Dakefile.t(), Target.Docker.t(), Type.tgid(), pipeline_uuid()) :: :ok
  defp build_dask_job_docker(%Run{} = run, %Dakefile{} = dakefile, %Target.Docker{} = docker, tgid, pipeline_uuid) do
    build_dask_job_docker_imports(run, docker, pipeline_uuid)

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
    docker_build(run, tgid, args)

    if run.shell and tgid == run.tgid do
      IO.puts("\nStarting interactive shell in #{run.tgid}:\n")

      docker_shell(tgid, pipeline_uuid)
    end

    if run.output do
      outputs =
        docker.directives
        |> Enum.filter(&match?(%Directive.Output{}, &1))
        |> Enum.map(& &1.dir)

      docker_output(run, tgid, pipeline_uuid, outputs)
    end

    :ok
  end

  @spec build_dask_job_docker_imports(Run.t(), Target.Docker.t(), pipeline_uuid()) :: :ok
  defp build_dask_job_docker_imports(%Run{} = run, %Target.Docker{} = docker, pipeline_uuid) do
    docker.directives
    |> Enum.filter(&match?(%Directive.Import{}, &1))
    |> Enum.each(fn %Directive.Import{} = import_ ->
      unless File.exists?(import_.ref) do
        raise Dake.Pipeline.Error, "cannot @import #{inspect(import_.ref)}"
      end

      cmd_res =
        Dake.cmd(
          %Run{
            ns: run.ns ++ [docker.tgid],
            tgid: import_.target,
            args: Enum.map(import_.args, &{&1.name, &1.default_value}),
            push: import_.push and run.push,
            output: import_.output and run.output,
            output_dir: import_.as,
            tag: fq_image(import_.as, pipeline_uuid),
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

  @spec build_dask_job_cleanup(Dask.t(), Dask.Job.id(), pipeline_uuid()) :: Dask.t()
  defp build_dask_job_cleanup(dask, cleanup_job_id, pipeline_uuid) do
    job_passthrough_fn = fn _, _ ->
      :ok
    end

    job_on_exit_fn = fn _, _, _ ->
      docker_cleanup(pipeline_uuid)
    end

    Dask.job(dask, cleanup_job_id, job_passthrough_fn, :infinity, job_on_exit_fn)
  end

  @spec docker_cleanup(pipeline_uuid()) :: :ok
  defp docker_cleanup(pipeline_uuid) do
    docker_rm_containers(pipeline_uuid)
    docker_rm_images(pipeline_uuid)
  end

  @spec docker_rm_images(pipeline_uuid()) :: :ok
  defp docker_rm_images(pipeline_uuid) do
    {cmd_out, 0} = System.cmd("docker", ["image", "ls", "*:#{pipeline_uuid}", "--format", "{{.Repository}}", "--quiet"])
    repositories = String.split(cmd_out, "\n", trim: true)

    if repositories != [] do
      images_ids = Enum.map(repositories, &fq_image(&1, pipeline_uuid))
      _ = System.cmd("docker", ["image", "rm" | images_ids], stderr_to_stdout: true)
    end

    :ok
  end

  @spec docker_rm_containers(pipeline_uuid()) :: :ok
  defp docker_rm_containers(pipeline_uuid) do
    cmd = ["container", "ls", "--all", "--filter", "name=#{fq_output_container(".*", pipeline_uuid)}", "--quiet"]
    {cmd_out, 0} = System.cmd("docker", cmd)
    containers_ids = String.split(cmd_out, "\n", trim: true)

    if containers_ids != [] do
      _ = System.cmd("docker", ["container", "rm" | containers_ids], stderr_to_stdout: true)
    end

    :ok
  end

  @spec docker_build(Run.t(), Type.tgid(), [String.t()]) :: :ok
  defp docker_build(%Run{} = run, tgid, args) do
    docker = System.find_executable("docker")
    args = [docker, "buildx", "build" | args]
    into = Reporter.collector(run.ns, tgid)

    case System.cmd("/usr/bin/dake_cmd.sh", args, stderr_to_stdout: true, into: into) do
      {_, 0} -> :ok
      {_, _exit_status} -> raise Dake.Pipeline.Error, "Target #{tgid} failed"
    end
  end

  @spec docker_build_cmd_args(Run.t(), Path.t(), Type.tgid(), pipeline_uuid(), Path.t()) :: [String.t()]
  defp docker_build_cmd_args(%Run{} = run, dockerfile_path, tgid, pipeline_uuid, build_ctx) do
    Enum.concat([
      ["--progress", "plain"],
      ["--file", dockerfile_path],
      ["--tag", fq_image(tgid, pipeline_uuid)],
      if(tgid == run.tgid and run.tag, do: ["--tag", run.tag], else: []),
      Enum.flat_map(run.args, fn {name, value} -> ["--build-arg", "#{name}=#{value}"] end),
      [build_ctx]
    ])
  end

  @spec docker_output(Run.t(), Type.tgid(), pipeline_uuid(), [Path.t()]) :: :ok
  defp docker_output(%Run{} = run, tgid, pipeline_uuid, outputs) do
    docker_image = fq_image(tgid, pipeline_uuid)
    tmp_container = fq_output_container(tgid, pipeline_uuid)

    container_create_cmd = ["container", "create", "--name", tmp_container, docker_image]
    {_, 0} = System.cmd("docker", container_create_cmd, stderr_to_stdout: true)

    Enum.each(outputs, fn output ->
      output_dir = Path.join(Dir.output(), run.output_dir)
      container_cp_cmd = ["container", "cp", "#{tmp_container}:#{output}", output_dir]
      into = Reporter.collector(run.ns, tgid)

      case System.cmd("docker", container_cp_cmd, stderr_to_stdout: true, into: into) do
        {_, 0} -> :ok
        {_, _exit_status} -> raise Dake.Pipeline.Error, "Target #{tgid} output copy failed"
      end

      Reporter.job_output(run.ns, tgid, "#{output} -> #{output_dir}")
    end)

    :ok
  end

  @spec docker_shell(Type.tgid(), pipeline_uuid()) :: :ok
  defp docker_shell(tgid, pipeline_uuid) do
    run_cmd_args = ["run", "--rm", "-t", "-i", "--entrypoint", "sh", fq_image(tgid, pipeline_uuid)]
    port_opts = [:nouse_stdio, :exit_status, args: run_cmd_args]
    port = Port.open({:spawn_executable, System.find_executable("docker")}, port_opts)

    receive do
      {^port, {:exit_status, _}} -> :ok
    end

    :ok
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

  @spec insert_builtin_global_args(Dakefile.t(), pipeline_uuid()) :: Dakefile.t()
  defp insert_builtin_global_args(%Dakefile{} = dakefile, pipeline_uuid) do
    %Dakefile{dakefile | args: dakefile.args ++ [%Docker.Arg{name: "DAKE_PIPELINE_UUID", default_value: pipeline_uuid}]}
  end

  @spec insert_builtin_docker_args(Target.Docker.t(), Path.t()) :: Target.Docker.t()
  defp insert_builtin_docker_args(%Target.Docker{} = docker, include_ctx_dir) do
    from_idx = Enum.find_index(docker.commands, &match?(%Docker.From{}, &1))
    {pre_from_cmds, [%Docker.From{} = from | post_from_cmds]} = Enum.split(docker.commands, from_idx)

    commands =
      pre_from_cmds ++ [from, %Docker.Arg{name: "DAKE_INCLUDE_CTX", default_value: include_ctx_dir}] ++ post_from_cmds

    %Target.Docker{docker | commands: commands}
  end

  @spec copy_includes_ctx(Dakefile.t()) :: :ok
  defp copy_includes_ctx(%Dakefile{} = dakefile) do
    dakefile.targets
    |> Enum.filter(&match?(%Target.Docker{included_from_ref: inc} when inc != nil, &1))
    |> List.flatten()
    |> Enum.each(fn %Target.Docker{included_from_ref: included_from_ref} ->
      include_ctx_dir = Path.join(Path.dirname(included_from_ref), "ctx")

      if File.exists?(include_ctx_dir) do
        dest = local_include_ctx_dir(dakefile, included_from_ref)

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

  @spec fq_targets_image_ref(pipeline_uuid(), Dakefile.t()) :: Dakefile.t()
  defp fq_targets_image_ref(pipeline_uuid, %Dakefile{} = dakefile) do
    update_fn = fn "+" <> tgid -> fq_image(tgid, pipeline_uuid) end

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

  @spec fq_image(Type.tgid(), pipeline_uuid()) :: String.t()
  defp fq_image(tgid, pipeline_uuid), do: "#{tgid}:#{pipeline_uuid}"

  @spec fq_output_container(Type.tgid(), pipeline_uuid()) :: String.t()
  defp fq_output_container(tgid, pipeline_uuid), do: "output-#{tgid}-#{pipeline_uuid}"

  @spec pipeline_uuid :: pipeline_uuid()
  defp pipeline_uuid do
    Base.encode32(:crypto.strong_rand_bytes(16), case: :lower, padding: false)
  end
end
