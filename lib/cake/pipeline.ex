defmodule Cake.Pipeline.Error do
  defexception [:message]
end

defmodule Cake.Pipeline do
  alias Cake.Cli.Run
  alias Cake.Parser.{Cakefile, Container, Directive, Target}
  alias Cake.Pipeline.Container, as: ContainerCmd
  alias Cake.{Dag, Dir, Reference, Reporter, Type}

  require Logger
  require Cake.Reporter.Status

  @spec build(Run.t(), Cakefile.t(), Dag.graph()) :: Dask.t()
  def build(%Run{} = run, %Cakefile{} = cakefile, graph) do
    pipeline_uuid = pipeline_uuid()

    Logger.info("#{inspect(cakefile.path)}", pipeline: pipeline_uuid)

    cakefile = fq_targets_image_ref(pipeline_uuid, cakefile)
    targets_map = Map.new(cakefile.targets, &{&1.tgid, &1})
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
        build_dask_job(run, cakefile, dask, tgid, target, pipeline_uuid)
      end)

    dask =
      Enum.reduce(pipeline_tgids, dask, fn tgid, dask ->
        upstream_tgids = Dag.upstream_tgids(graph, tgid)
        Dask.flow(dask, upstream_tgids, tgid)
      end)

    dask = build_dask_job_cleanup(dask, :cleanup, pipeline_uuid)
    Dask.flow(dask, run.tgid, :cleanup)
  end

  @spec build_dask_job(Run.t(), Cakefile.t(), Dask.t(), Type.tgid(), Cakefile.target(), Type.pipeline_uuid()) ::
          Dask.t()
  defp build_dask_job(%Run{} = run, %Cakefile{} = cakefile, dask, tgid, target, pipeline_uuid) do
    job_fn = fn ^tgid, _upstream_jobs_status ->
      Reporter.job_start(run.ns, tgid)

      case target do
        %Target.Alias{} ->
          :ok

        %Target.Container{} = container ->
          dask_job_container(run, cakefile, container, tgid, pipeline_uuid)
      end

      :ok
    end

    job_on_exit_fn = fn ^tgid, _upstream_results, job_exec_result ->
      case job_exec_result do
        {:job_ok, :ok} ->
          Reporter.job_end(run.ns, tgid, Reporter.Status.ok())

        :job_timeout ->
          Reporter.job_end(run.ns, tgid, Reporter.Status.timeout())

        {:job_error, %Cake.Pipeline.Error{} = err, _stacktrace} ->
          Reporter.job_end(run.ns, tgid, Reporter.Status.error(err.message, nil))

        {:job_error, reason, stacktrace} ->
          Reporter.job_end(run.ns, tgid, Reporter.Status.error(reason, stacktrace))

        :job_skipped ->
          :ok
      end
    end

    Dask.job(dask, tgid, job_fn, :infinity, job_on_exit_fn)
  end

  @spec dask_job_container(Run.t(), Cakefile.t(), Target.Container.t(), Type.tgid(), Type.pipeline_uuid()) :: :ok
  defp dask_job_container(%Run{} = run, %Cakefile{} = cakefile, %Target.Container{} = container, tgid, pipeline_uuid) do
    Logger.info("start for #{inspect(tgid)}", pipeline: pipeline_uuid)

    dask_job_container_imports(run, container, pipeline_uuid)

    job_uuid = to_string(System.unique_integer([:positive]))
    container_build_ctx_dir = Path.dirname(cakefile.path)

    build_relative_include_ctx_dir =
      if container.included_from_ref do
        include_ctx_dir = Dir.local_include_ctx_dir(cakefile.path, container.included_from_ref)
        Path.relative_to(include_ctx_dir, container_build_ctx_dir)
      else
        ""
      end

    cakefile = insert_builtin_global_args(cakefile, pipeline_uuid)
    container = insert_builtin_container_args(container, build_relative_include_ctx_dir)

    containerfile_path = Path.join(Dir.tmp(), "#{job_uuid}-#{tgid}.Containerfile")
    write_containerfile(cakefile.args, container, containerfile_path)

    args = container_build_cmd_args(run, containerfile_path, tgid, pipeline_uuid, container_build_ctx_dir)
    ContainerCmd.container_build(run, tgid, args, pipeline_uuid)

    if run.shell and tgid == run.tgid do
      Reporter.job_notice(run.ns, run.tgid, "\nStarting interactive shell:\n")
      ContainerCmd.container_shell(tgid, pipeline_uuid)
    end

    if run.output do
      outputs =
        container.directives
        |> Enum.filter(&match?(%Directive.Output{}, &1))
        |> Enum.map(& &1.dir)

      ContainerCmd.container_output(run, tgid, pipeline_uuid, outputs)
    end

    :ok
  end

  @spec dask_job_container_imports(Run.t(), Target.Container.t(), Type.pipeline_uuid()) :: :ok
  defp dask_job_container_imports(%Run{} = run, %Target.Container{} = container, pipeline_uuid) do
    container.directives
    |> Enum.filter(&match?(%Directive.Import{}, &1))
    |> Enum.each(fn %Directive.Import{} = import_ ->
      import_cakefile_path =
        case Reference.get_import(import_) do
          {:ok, import_cakefile_path} -> import_cakefile_path
          {:error, reason} -> raise Cake.Pipeline.Error, "cannot @import #{inspect(import_.ref)}: #{reason}"
        end

      unless File.exists?(import_cakefile_path) do
        raise Cake.Pipeline.Error, "cannot @import #{inspect(import_.ref)}"
      end

      Logger.info(
        "running pipeline for imported target #{inspect(import_.target)} cakefile=#{inspect(import_cakefile_path)}",
        pipeline: pipeline_uuid
      )

      cmd_res =
        Cake.cmd(
          %Run{
            ns: run.ns ++ [container.tgid],
            tgid: import_.target,
            args: Enum.map(import_.args, &{&1.name, &1.default_value}),
            push: import_.push and run.push,
            output: import_.output and run.output,
            output_dir: import_.as,
            tag: ContainerCmd.fq_image(import_.as, pipeline_uuid),
            timeout: :infinity,
            parallelism: run.parallelism,
            verbose: run.verbose,
            save_logs: run.save_logs,
            shell: false
          },
          import_.ref
        )

      case cmd_res do
        :ok ->
          :ok

        {:error, reason} ->
          raise Cake.Pipeline.Error, "failed @import #{inspect(import_.ref)} build: #{inspect(reason)}"

        :timeout ->
          raise Cake.Pipeline.Error, "timeout"
      end
    end)
  end

  @spec build_dask_job_cleanup(Dask.t(), Dask.Job.id(), Type.pipeline_uuid()) :: Dask.t()
  defp build_dask_job_cleanup(dask, cleanup_job_id, pipeline_uuid) do
    job_passthrough_fn = fn _, _ ->
      :ok
    end

    job_on_exit_fn = fn _, _, _ ->
      ContainerCmd.container_cleanup(pipeline_uuid)
    end

    Dask.job(dask, cleanup_job_id, job_passthrough_fn, :infinity, job_on_exit_fn)
  end

  @spec container_build_cmd_args(Run.t(), Path.t(), Type.tgid(), Type.pipeline_uuid(), Path.t()) :: [String.t()]
  defp container_build_cmd_args(%Run{} = run, containerfile_path, tgid, pipeline_uuid, build_ctx) do
    Enum.concat([
      ["--progress", "plain"],
      ["--file", containerfile_path],
      ["--tag", ContainerCmd.fq_image(tgid, pipeline_uuid)],
      if(tgid == run.tgid and run.tag, do: ["--tag", run.tag], else: []),
      Enum.flat_map(run.args, fn {name, value} -> ["--build-arg", "#{name}=#{value}"] end),
      [build_ctx]
    ])
  end

  @spec push_target?(Cakefile.target()) :: boolean()
  defp push_target?(%Target.Alias{}), do: false

  defp push_target?(%Target.Container{} = container) do
    Enum.any?(container.directives, &match?(%Directive.Push{}, &1))
  end

  @spec validate_cmd(Run.t(), Cakefile.target()) :: :ok | no_return()
  defp validate_cmd(%Run{} = run, target) do
    if run.push and push_target?(target) do
      Cake.System.halt(:error, "@push target #{run.tgid} can be executed only via 'run --push'")
    end

    if run.shell and match?(%Target.Alias{}, target) do
      Cake.System.halt(:error, "cannot shell into and \"alias\" target")
    end

    :ok
  end

  @spec insert_builtin_global_args(Cakefile.t(), Type.pipeline_uuid()) :: Cakefile.t()
  defp insert_builtin_global_args(%Cakefile{} = cakefile, pipeline_uuid) do
    %Cakefile{
      cakefile
      | args: cakefile.args ++ [%Container.Arg{name: "CAKE_PIPELINE_UUID", default_value: pipeline_uuid}]
    }
  end

  @spec insert_builtin_container_args(Target.Container.t(), Path.t()) :: Target.Container.t()
  defp insert_builtin_container_args(%Target.Container{} = container, include_ctx_dir) do
    from_idx = Enum.find_index(container.commands, &match?(%Container.From{}, &1))
    {pre_from_cmds, [%Container.From{} = from | post_from_cmds]} = Enum.split(container.commands, from_idx)

    commands =
      pre_from_cmds ++
        [from, %Container.Arg{name: "CAKE_INCLUDE_CTX", default_value: include_ctx_dir}] ++ post_from_cmds

    %Target.Container{container | commands: commands}
  end

  @spec write_containerfile([Container.Arg.t()], Target.Container.t(), Path.t()) :: :ok
  defp write_containerfile(args, %Target.Container{} = container, path) do
    containerfile = Enum.map_join(args ++ container.commands, "\n", &Container.Fmt.fmt(&1))
    File.write!(path, containerfile)

    :ok
  end

  @spec fq_targets_image_ref(Type.pipeline_uuid(), Cakefile.t()) :: Cakefile.t()
  defp fq_targets_image_ref(pipeline_uuid, %Cakefile{} = cakefile) do
    update_fn = fn "+" <> tgid -> ContainerCmd.fq_image(tgid, pipeline_uuid) end

    cakefile =
      update_in(
        cakefile,
        [
          Access.key!(:targets),
          Access.filter(&match?(%Target.Container{}, &1)),
          Access.key!(:commands),
          Access.filter(&match?(%Container.From{image: "+" <> _}, &1)),
          Access.key!(:image)
        ],
        update_fn
      )

    update_in(
      cakefile,
      [
        Access.key!(:targets),
        Access.filter(&match?(%Target.Container{}, &1)),
        Access.key!(:commands),
        Access.filter(&match?(%Container.Command{instruction: "COPY"}, &1)),
        Access.key!(:options),
        Access.filter(&match?(%Container.Command.Option{name: "from"}, &1)),
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
