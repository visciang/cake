defmodule Dake.Pipeline.Error do
  defexception [:message]
end

defmodule Dake.Pipeline do
  alias Dake.Cli.Run
  alias Dake.Parser.{Dakefile, Directive, Docker, Target}
  alias Dake.{Const, Dag, Reporter, Type}

  require Dake.Reporter.Status
  require Dake.Const

  @typep uuid :: String.t()

  @spec build(Run.t(), Dakefile.t(), Dag.graph()) :: Dask.t()
  def build(%Run{} = run, %Dakefile{} = dakefile, graph) do
    setup_dirs(run)
    build_dask_pipeline(run, dakefile, graph)
  end

  @spec setup_dirs(Run.t()) :: :ok
  defp setup_dirs(%Run{} = run) do
    dirs = [Const.tmp_dir()]
    dirs = dirs ++ if(run.output, do: [Const.output_dir()], else: [])

    Enum.each(dirs, fn dir ->
      File.rm_rf!(dir)
      File.mkdir_p!(dir)
    end)
  end

  @spec cleanup_dirs :: :ok
  defp cleanup_dirs do
    File.rm_rf!(Const.tmp_dir())

    :ok
  end

  @spec build_dask_pipeline(Run.t(), Dakefile.t(), Dag.graph()) :: Dask.t()
  defp build_dask_pipeline(%Run{} = run, %Dakefile{} = dakefile, graph) do
    uuid = uuid()
    dakefile = fq_dakefile_targets(uuid, dakefile)
    targets_map = Map.new(dakefile.targets, &{&1.tgid, &1})
    pipeline_tgids = Dag.reaching_tgids(graph, run.tgid)

    validate_cmd(run, Map.fetch!(targets_map, run.tgid))

    pipeline_tgids =
      if run.push do
        pipeline_tgids
      else
        Enum.reject(pipeline_tgids, &push_target?(targets_map[&1]))
      end

    dask =
      Enum.reduce(pipeline_tgids, Dask.new(), fn tgid, dask ->
        target = Map.fetch!(targets_map, tgid)
        build_dask_job(run, dakefile, dask, tgid, target, uuid)
      end)

    dask =
      Enum.reduce(pipeline_tgids, dask, fn tgid, dask ->
        upstream_tgids = Dag.upstream_tgids(graph, tgid)
        Dask.flow(dask, upstream_tgids, tgid)
      end)

    dask = build_dask_job_cleanup(dask, :cleanup, uuid)
    Dask.flow(dask, run.tgid, :cleanup)
  end

  @spec build_dask_job(Run.t(), Dakefile.t(), Dask.t(), Type.tgid(), Dakefile.target(), uuid()) :: Dask.t()
  defp build_dask_job(%Run{} = run, %Dakefile{} = dakefile, dask, tgid, target, uuid) do
    job_fn = fn ^tgid, _upstream_jobs_status ->
      case target do
        %Target.Alias{} ->
          :ok

        %Target.Docker{} = docker ->
          build_dask_job_docker(run, dakefile, docker, tgid, uuid)
      end

      :ok
    end

    job_on_exit_fn = fn ^tgid, _upstream_results, job_exec_result, elapsed_time_ms ->
      elapsed_time_s = elapsed_time_ms * 1_000

      case job_exec_result do
        {:job_ok, :ok} ->
          Reporter.job_report(tgid, Reporter.Status.ok(), nil, elapsed_time_s)

        :job_timeout ->
          Reporter.job_report(tgid, Reporter.Status.timeout(), nil, elapsed_time_s)

        {:job_error, %Dake.Pipeline.Error{} = err, _stacktrace} ->
          Reporter.job_report(tgid, Reporter.Status.error(err.message, nil), nil, elapsed_time_s)

        {:job_error, reason, stacktrace} ->
          error_message = "Internal dake error"
          Reporter.job_report(tgid, Reporter.Status.error(reason, stacktrace), error_message, elapsed_time_s)

        :job_skipped ->
          :ok
      end
    end

    Dask.job(dask, tgid, job_fn, :infinity, job_on_exit_fn)
  end

  @spec build_dask_job_docker(Run.t(), Dakefile.t(), Target.Docker.t(), Type.tgid(), uuid()) :: :ok
  defp build_dask_job_docker(%Run{} = run, %Dakefile{} = dakefile, %Target.Docker{} = docker, tgid, uuid) do
    build_dask_job_docker_imports(run, docker, uuid)

    if docker.included_from_ref do
      copy_included_ref_ctx(docker.included_from_ref)
    end

    dakefile = insert_builtin_args(dakefile, uuid)

    dockerfile_path = Path.join(Const.tmp_dir(), "Dockerfile.#{tgid}")
    write_dockerfile(dakefile.args, docker, dockerfile_path)

    args = docker_build_cmd_args(run, dockerfile_path, tgid, uuid)
    docker_build(tgid, args)

    if run.shell and tgid == run.tgid do
      IO.puts("\nStarting interactive shell in #{run.tgid}:\n")

      docker_shell(tgid, uuid)
    end

    if run.output do
      outputs =
        docker.directives
        |> Enum.filter(&match?(%Directive.Output{}, &1))
        |> Enum.map(& &1.dir)

      docker_output(tgid, uuid, outputs)
    end

    :ok
  end

  @spec build_dask_job_docker_imports(Run.t(), Target.Docker.t(), uuid()) :: :ok
  defp build_dask_job_docker_imports(%Run{} = run, %Target.Docker{} = docker, uuid) do
    docker.directives
    |> Enum.filter(&match?(%Directive.Import{}, &1))
    |> Enum.each(fn %Directive.Import{} = import_ ->
      unless File.exists?(import_.ref) do
        raise Dake.Pipeline.Error, "cannot @import #{inspect(import_.ref)}"
      end

      dir = import_.ref |> Path.dirname()

      # TODO parallelism -> limiter
      # dask.limiter deve essere quello principale
      cmd_res =
        Dake.cmd(
          %Run{
            tgid: import_.target,
            args: Enum.map(import_.args, &{&1.name, &1.default_value}),
            push: false,
            output: nil,
            tag: fq_image(import_.target, uuid),
            timeout: :infinity,
            parallelism: run.parallelism,
            verbose: run.verbose,
            save_logs: run.save_logs,
            shell: false
          },
          dir
        )

      case cmd_res do
        :ok -> :ok
        {:error, _} -> raise Dake.Pipeline.Error, "failed @import #{inspect(import_.ref)} build"
        :timeout -> raise Dake.Pipeline.Error, "timeout"
      end
    end)
  end

  @spec build_dask_job_cleanup(Dask.t(), Dask.Job.id(), uuid()) :: Dask.t()
  defp build_dask_job_cleanup(dask, cleanup_job_id, uuid) do
    job_passthrough_fn = fn _, _ ->
      :ok
    end

    job_on_exit_fn = fn _, _, _, _ ->
      cleanup_dirs()
      docker_cleanup(uuid)
    end

    Dask.job(dask, cleanup_job_id, job_passthrough_fn, :infinity, job_on_exit_fn)
  end

  @spec docker_cleanup(uuid()) :: :ok
  defp docker_cleanup(uuid) do
    docker_rm_containers(uuid)
    docker_rm_images(uuid)
  end

  @spec docker_rm_images(uuid()) :: :ok
  defp docker_rm_images(uuid) do
    {cmd_out, 0} = System.cmd("docker", ["image", "ls", "*:#{uuid}", "--format", "{{.Repository}}", "--quiet"])
    repositories = String.split(cmd_out, "\n", trim: true)

    if repositories != [] do
      images_ids = Enum.map(repositories, &fq_image(&1, uuid))
      _ = System.cmd("docker", ["image", "rm" | images_ids], stderr_to_stdout: true)
    end

    :ok
  end

  @spec docker_rm_containers(uuid()) :: :ok
  defp docker_rm_containers(uuid) do
    cmd = ["container", "ls", "--all", "--filter", "name=#{fq_output_container(".*", uuid)}", "--quiet"]
    {cmd_out, 0} = System.cmd("docker", cmd)
    containers_ids = String.split(cmd_out, "\n", trim: true)

    if containers_ids != [] do
      _ = System.cmd("docker", ["container", "rm" | containers_ids], stderr_to_stdout: true)
    end

    :ok
  end

  @spec docker_build(Type.tgid(), [String.t()]) :: :ok
  defp docker_build(tgid, args) do
    docker = System.find_executable("docker")
    args = [docker, "buildx", "build" | args]

    case System.cmd("/usr/bin/dake_cmd.sh", args, stderr_to_stdout: true, into: Reporter.collector(tgid)) do
      {_, 0} -> :ok
      {_, _exit_status} -> raise Dake.Pipeline.Error, "Target #{tgid} failed"
    end
  end

  @spec docker_build_cmd_args(Run.t(), Path.t(), Type.tgid(), uuid()) :: [String.t()]
  defp docker_build_cmd_args(%Run{} = run, dockerfile_path, tgid, uuid) do
    Enum.concat([
      ["--progress", "plain"],
      ["--file", dockerfile_path],
      ["--tag", fq_image(tgid, uuid)],
      if(tgid == run.tgid and run.tag, do: ["--tag", run.tag], else: []),
      Enum.flat_map(run.args, fn {name, value} -> ["--build-arg", "#{name}=#{value}"] end),
      ["."]
    ])
  end

  @spec docker_output(Type.tgid(), uuid(), [Path.t()]) :: :ok
  defp docker_output(tgid, uuid, outputs) do
    docker_image = fq_image(tgid, uuid)
    tmp_container = fq_output_container(tgid, uuid)

    container_create_cmd = ["container", "create", "--name", tmp_container, docker_image]
    {_, 0} = System.cmd("docker", container_create_cmd, stderr_to_stdout: true)

    Enum.each(outputs, fn output ->
      container_cp_cmd = ["container", "cp", "#{tmp_container}:#{output}", Const.output_dir()]

      case System.cmd("docker", container_cp_cmd, stderr_to_stdout: true, into: Reporter.collector(tgid)) do
        {_, 0} -> :ok
        {_, _exit_status} -> raise Dake.Pipeline.Error, "Target #{tgid} output copy failed"
      end
    end)

    :ok
  end

  @spec docker_shell(Type.tgid(), uuid()) :: :ok
  defp docker_shell(tgid, uuid) do
    run_cmd_args = ["run", "--rm", "-t", "-i", "--entrypoint", "sh", fq_image(tgid, uuid)]
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

  @spec insert_builtin_args(Dakefile.t(), uuid()) :: Dakefile.t()
  defp insert_builtin_args(%Dakefile{} = dakefile, uuid) do
    builtin_args = [
      %Docker.Arg{name: "DAKE_UUID", default_value: uuid}
    ]

    dakefile
    |> update_in(
      [Access.key(:args)],
      &(&1 ++ builtin_args)
    )
    |> update_in(
      [
        Access.key!(:targets),
        Access.filter(&match?(%Target.Docker{}, &1)),
        Access.key!(:commands)
      ],
      fn [%Docker.From{} = from | rest_commands] ->
        [from | builtin_args] ++ [rest_commands]
      end
    )
  end

  @spec copy_included_ref_ctx(String.t()) :: :ok
  defp copy_included_ref_ctx(included_ref) do
    include_ctx_dir = Path.join(Path.dirname(included_ref), Const.tmp_dir())

    if File.exists?(include_ctx_dir) do
      File.cp_r!(include_ctx_dir, Const.tmp_dir())
    end

    :ok
  end

  @spec write_dockerfile([Docker.Arg.t()], Target.Docker.t(), Path.t()) :: :ok
  defp write_dockerfile(args, %Target.Docker{} = docker, path) do
    dockerfile = Enum.map_join(args ++ docker.commands, "\n", &Docker.Fmt.fmt(&1))
    File.write!(path, dockerfile)

    :ok
  end

  @spec fq_dakefile_targets(uuid, Dakefile.t()) :: Dakefile.t()
  defp fq_dakefile_targets(uuid, %Dakefile{} = dakefile) do
    update_fn = fn "+" <> tgid -> fq_image(tgid, uuid) end

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

  @spec fq_image(Type.tgid(), uuid()) :: String.t()
  defp fq_image(tgid, uuid), do: "#{tgid}:#{uuid}"

  @spec fq_output_container(Type.tgid(), uuid()) :: String.t()
  defp fq_output_container(tgid, uuid), do: "output-#{tgid}-#{uuid}"

  @spec uuid :: uuid()
  defp uuid do
    Base.encode32(:crypto.strong_rand_bytes(16), case: :lower, padding: false)
  end
end
