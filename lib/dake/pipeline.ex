defmodule Dake.Pipeline do
  alias Dake.CliArgs.Run
  alias Dake.Parser.{Dakefile, Directive, Docker, Target}
  alias Dake.{Dag, Type}

  @typep targets_map :: %{Type.tgid() => Dakefile.target()}
  @typep uuid :: String.t()

  @dake_dir ".dake"
  @dake_output_dir ".dake_output"

  @spec build(Run.t(), Dakefile.t(), Dag.graph()) :: Dask.t()
  def build(%Run{} = run, %Dakefile{} = dakefile, graph) do
    setup_dirs()
    uuid = uuid()
    dakefile = qualify_dakefile_targets(uuid, dakefile)
    build_dask_pipeline(uuid, run, dakefile, graph)
  end

  @spec setup_dirs :: :ok
  defp setup_dirs do
    [@dake_dir, @dake_output_dir]
    |> Enum.each(fn dir ->
      File.rm_rf!(dir)
      File.mkdir!(dir)
    end)
  end

  @spec cleanup_dirs :: :ok
  defp cleanup_dirs do
    File.rm_rf!(@dake_dir)
    :ok
  end

  @spec qualify_dakefile_targets(uuid, Dakefile.t()) :: Dakefile.t()
  defp qualify_dakefile_targets(uuid, %Dakefile{} = dakefile) do
    update_fn = fn "+" <> tgid -> fq_tgid(tgid, uuid) end

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

  @spec fq_tgid(Type.tgid(), uuid()) :: String.t()
  defp fq_tgid(tgid, uuid), do: "#{tgid}:#{uuid}"

  @spec build_dask_pipeline(uuid(), Run.t(), Dakefile.t(), Dag.graph()) :: Dask.t()
  defp build_dask_pipeline(uuid, %Run{} = run, %Dakefile{} = dakefile, graph) do
    targets_map = Map.new(dakefile.targets, &{&1.tgid, &1})
    pipeline_tgids = Dag.reaching_tgids(graph, run.tgid)

    if run.push and push_target?(targets_map[run.tgid]) do
      Dake.System.halt(:error, "@push target #{run.tgid} can be executed only via 'run --push'")
    end

    pipeline_tgids =
      if run.push do
        Enum.reject(pipeline_tgids, &push_target?(targets_map[&1]))
      else
        pipeline_tgids
      end

    dask =
      Enum.reduce(pipeline_tgids, Dask.new(), fn tgid, dask ->
        build_dask_job(run, dakefile, dask, tgid, targets_map, uuid)
      end)

    dask =
      Enum.reduce(pipeline_tgids, dask, fn tgid, dask ->
        upstream_tgids = Dag.upstream_tgids(graph, tgid)
        Dask.flow(dask, upstream_tgids, tgid)
      end)

    dask = build_dask_job_cleanup(dask, :cleanup, uuid)
    Dask.flow(dask, run.tgid, :cleanup)
  end

  @spec build_dask_job(Run.t(), Dakefile.t(), Dask.t(), Type.tgid(), targets_map(), uuid()) :: Dask.t()
  defp build_dask_job(%Run{} = run, %Dakefile{} = dakefile, dask, tgid, targets_map, uuid) do
    Dask.job(dask, tgid, fn ^tgid, _upstream_jobs_status ->
      case Map.fetch!(targets_map, tgid) do
        %Target.Alias{} ->
          :ok

        %Target.Docker{} = docker ->
          build_dask_job_docker(run, dakefile, docker, tgid, uuid)
      end
    end)
  end

  @spec build_dask_job_docker(Run.t(), Dakefile.t(), Target.Docker.t(), Type.tgid(), uuid()) :: :ok
  defp build_dask_job_docker(%Run{} = run, %Dakefile{} = dakefile, %Target.Docker{} = docker, tgid, uuid) do
    if docker.included_from_ref do
      copy_included_ref_ctx(docker.included_from_ref)
    end

    dockerfile_path = Path.join(@dake_dir, "/Dockerfile.#{tgid}")
    write_dockerfile(dakefile.args, docker, dockerfile_path)

    args = docker_build_cmd_args(run, dockerfile_path, tgid, uuid)
    docker_build(tgid, args)

    if run.output do
      outputs =
        docker.directives
        |> Enum.filter(&match?(%Directive.Output{}, &1))
        |> Enum.map(& &1.dir)

      docker_output(tgid, uuid, outputs)
    end

    :ok
  end

  @spec build_dask_job_cleanup(Dask.t(), Dask.Job.id(), uuid()) :: Dask.t()
  defp build_dask_job_cleanup(dask, cleanup_job_id, uuid) do
    job_passthrough_fn = fn _, _ ->
      :ok
    end

    job_on_exit_fn = fn _, _, _, _ ->
      cleanup_dirs()
      docker_cleanup_images(uuid)
    end

    Dask.job(dask, cleanup_job_id, job_passthrough_fn, :infinity, job_on_exit_fn)
  end

  @spec docker_cleanup_images(uuid()) :: :ok
  defp docker_cleanup_images(uuid) do
    {res, 0} = System.cmd("docker", ["image", "ls", "--format", "{{.ID}}", "*:#{uuid}"])
    images = res |> String.trim() |> String.split("\n")
    {_, 0} = System.cmd("docker", ["image", "rm" | images])
    :ok
  end

  @spec docker_build(Type.tgid(), [String.t()]) :: :ok
  defp docker_build(tgid, args) do
    case System.cmd("docker", args, into: IO.stream()) do
      {_, 0} -> :ok
      {_, _exit_status} -> raise "Target #{tgid} failed"
    end
  end

  @spec docker_output(Type.tgid(), uuid(), [Path.t()]) :: :ok
  defp docker_output(tgid, uuid, outputs) do
    docker_image = fq_tgid(tgid, uuid)
    tmp_container = "output-#{tgid}-#{uuid}"

    {_, 0} = System.cmd("docker", ["create", "--name", tmp_container, docker_image])

    Enum.each(outputs, fn output ->
      case System.cmd("docker", ["container", "cp", "#{tmp_container}:#{output}", @dake_output_dir], into: IO.stream()) do
        {_, 0} -> :ok
        {_, _exit_status} -> raise "Target #{tgid} output copy failed"
      end
    end)

    {_, 0} = System.cmd("docker", ["container", "rm", tmp_container])

    :ok
  end

  @spec docker_build_cmd_args(Run.t(), Path.t(), Type.tgid(), uuid()) :: [String.t()]
  defp docker_build_cmd_args(%Run{} = run, dockerfile_path, tgid, uuid) do
    Enum.concat([
      ["buildx", "build"],
      ["--progress", "plain"],
      ["--file", dockerfile_path],
      ["--tag", fq_tgid(tgid, uuid)],
      if(tgid == run.tgid and run.tag, do: ["--tag", run.tag], else: []),
      Enum.flat_map(run.args, fn {name, value} -> ["--build-arg", "#{name}=#{value}"] end),
      ["."]
    ])
  end

  @spec uuid :: uuid()
  defp uuid do
    :crypto.strong_rand_bytes(16)
    |> Base.encode32(case: :lower, padding: false)
  end

  @spec push_target?(Dakefile.target()) :: boolean()
  defp push_target?(%Target.Alias{}), do: false

  defp push_target?(%Target.Docker{} = docker) do
    Enum.any?(docker.directives, &match?(%Directive.Push{}, &1))
  end

  @spec copy_included_ref_ctx(String.t()) :: :ok
  defp copy_included_ref_ctx(included_ref) do
    include_ctx_dir = Path.join(Path.dirname(included_ref), @dake_dir)

    if File.exists?(include_ctx_dir) do
      File.cp_r!(include_ctx_dir, @dake_dir)
    end

    :ok
  end

  @spec write_dockerfile([Docker.Arg.t()], Target.Docker.t(), Path.t()) :: :ok
  defp write_dockerfile(args, %Target.Docker{} = docker, path) do
    dockerfile = Enum.map_join(args ++ docker.commands, "\n", &Docker.Fmt.fmt(&1))
    File.write!(path, dockerfile)

    :ok
  end
end
