defmodule Cake.Pipeline.Error do
  defexception [:message]
end

defmodule Cake.Pipeline do
  alias Cake.Cli.Run
  alias Cake.{Dag, Dir, Reporter, Type}
  alias Cake.Parser.Cakefile
  alias Cake.Parser.Directive.{DevShell, Output, Push}
  alias Cake.Parser.Target.{Alias, Container}
  alias Cake.Parser.Target.Container.{Arg, Command, Fmt, From}

  require Cake.Reporter.Status
  require Logger

  @spec container :: module()
  defp container, do: Application.get_env(:cake, :container_manager, Cake.Pipeline.Docker)

  @spec build(Run.t(), Cakefile.t(), Dag.graph()) :: Dask.t()
  def build(%Run{} = run, %Cakefile{} = cakefile, graph) do
    pipeline_uuid = pipeline_uuid()

    Logger.info("#{inspect(cakefile.path)}", pipeline: pipeline_uuid)

    cakefile = fq_targets_image_ref(pipeline_uuid, cakefile)
    targets_map = Map.new(cakefile.targets, &{&1.tgid, &1})
    pipeline_tgids = Dag.reaching_tgids(graph, run.tgid)
    pipeline_target = Map.fetch!(targets_map, run.tgid)

    validate_cmd(run, pipeline_target)

    pipeline_tgids =
      if run.push do
        pipeline_tgids
      else
        Enum.reject(pipeline_tgids, &push_target?(targets_map[&1]))
      end

    dask =
      for tgid <- pipeline_tgids, reduce: Dask.new() do
        dask ->
          target = Map.fetch!(targets_map, tgid)
          build_dask_job(run, cakefile, dask, tgid, target, pipeline_uuid)
      end

    dask =
      for tgid <- pipeline_tgids, reduce: dask do
        dask ->
          upstream_tgids = Dag.upstream_tgids(graph, tgid)
          Dask.flow(dask, upstream_tgids, tgid)
      end

    dask = build_dask_job_cleanup(dask, :cleanup, pipeline_uuid)
    Dask.flow(dask, run.tgid, :cleanup)
  end

  @spec build_dask_job(Run.t(), Cakefile.t(), Dask.t(), Type.tgid(), Cakefile.target(), Type.pipeline_uuid()) ::
          Dask.t()
  defp build_dask_job(%Run{} = run, %Cakefile{} = cakefile, dask, tgid, target, pipeline_uuid) do
    job_fn = fn ^tgid, _upstream_jobs_status ->
      Reporter.job_start(tgid)

      case target do
        %Alias{} ->
          :ok

        %Container{} = target ->
          dask_job(run, cakefile, target, tgid, pipeline_uuid)
      end

      :ok
    end

    job_on_exit_fn = fn ^tgid, _upstream_results, job_exec_result ->
      case job_exec_result do
        {:job_ok, :ok} ->
          Reporter.job_end(tgid, Reporter.Status.ok())

        # We do not apply a timeout on single jobs, only a global pipeline timeout:
        # See Dask.job(_, _, _, :infinity, _) below
        #
        # :job_timeout ->
        #   Reporter.job_end(tgid, Reporter.Status.timeout())

        # coveralls-ignore-start

        :job_skipped ->
          :ok

        {:job_error, %Cake.Pipeline.Error{} = err, _stacktrace} ->
          Reporter.job_end(tgid, Reporter.Status.error(err.message, nil))

        # coveralls-ignore-stop

        {:job_error, reason, stacktrace} ->
          Reporter.job_end(tgid, Reporter.Status.error(reason, stacktrace))
      end
    end

    Dask.job(dask, tgid, job_fn, :infinity, job_on_exit_fn)
  end

  @spec dask_job(Run.t(), Cakefile.t(), Container.t(), Type.tgid(), Type.pipeline_uuid()) :: :ok
  defp dask_job(%Run{} = run, %Cakefile{} = cakefile, %Container{} = target, tgid, pipeline_uuid) do
    Logger.info("start for #{inspect(tgid)}", pipeline: pipeline_uuid)

    job_uuid = to_string(System.unique_integer([:positive]))
    container_build_ctx_dir = Path.dirname(cakefile.path)

    build_relative_include_ctx_dir = (target.included_from_ref || ".") |> Path.dirname() |> Path.join("ctx")

    cakefile = insert_builtin_global_args(cakefile, pipeline_uuid)
    target = insert_builtin_container_args(target, build_relative_include_ctx_dir)

    containerfile_path = Path.join(Dir.tmp(), "#{job_uuid}-#{tgid}.Dockerfile")
    write_containerfile(cakefile.args, target, containerfile_path)

    tags = if tgid == run.tgid and run.tag, do: [run.tag], else: []
    tags = [container().fq_image(tgid, pipeline_uuid) | tags]
    build_args = run.args
    no_cache = run.push and push_target?(target)
    secrets = run.secrets

    container().build(
      tgid,
      tags,
      build_args,
      containerfile_path,
      no_cache,
      secrets,
      container_build_ctx_dir,
      pipeline_uuid
    )

    # coveralls-ignore-start

    if run.shell and tgid == run.tgid do
      devshell? = Enum.any?(target.directives, &match?(%DevShell{}, &1))

      Reporter.job_shell_start(run.tgid)
      container().shell(tgid, pipeline_uuid, devshell?)
      Reporter.job_shell_end(run.tgid)
    end

    # coveralls-ignore-stop

    if run.output do
      output_paths = for %Output{path: path} <- target.directives, do: path
      container().output(tgid, pipeline_uuid, output_paths, run.output_dir)
    end

    :ok
  end

  @spec build_dask_job_cleanup(Dask.t(), Dask.Job.id(), Type.pipeline_uuid()) :: Dask.t()
  defp build_dask_job_cleanup(dask, cleanup_job_id, pipeline_uuid) do
    job_passthrough_fn = fn _, _ ->
      :ok
    end

    job_on_exit_fn = fn _, _, _ ->
      container().cleanup(pipeline_uuid)
    end

    Dask.job(dask, cleanup_job_id, job_passthrough_fn, :infinity, job_on_exit_fn)
  end

  @spec push_target?(Cakefile.target()) :: boolean()
  defp push_target?(%Container{} = target), do: Enum.any?(target.directives, &match?(%Push{}, &1))
  defp push_target?(_target), do: false

  @spec validate_cmd(Run.t(), Cakefile.target()) :: :ok | no_return()
  defp validate_cmd(%Run{} = run, target) do
    if not run.push and push_target?(target) do
      Cake.System.halt(:error, "@push target #{run.tgid} can be executed only via 'run --push'")
    end

    # coveralls-ignore-start

    if run.shell and match?(%Alias{}, target) do
      Cake.System.halt(:error, "cannot shell into and \"alias\" target")
    end

    # coveralls-ignore-stop

    :ok
  end

  @spec insert_builtin_global_args(Cakefile.t(), Type.pipeline_uuid()) :: Cakefile.t()
  defp insert_builtin_global_args(%Cakefile{} = cakefile, pipeline_uuid) do
    %Cakefile{
      cakefile
      | args: cakefile.args ++ [%Arg{name: "CAKE_PIPELINE_UUID", default_value: pipeline_uuid}]
    }
  end

  @spec insert_builtin_container_args(Container.t(), Path.t()) :: Container.t()
  defp insert_builtin_container_args(%Container{} = target, include_ctx_dir) do
    from_idx = Enum.find_index(target.commands, &match?(%From{}, &1))
    {pre_from_cmds, [%From{} = from | post_from_cmds]} = Enum.split(target.commands, from_idx)

    commands =
      pre_from_cmds ++
        [from, %Arg{name: "CAKE_INCLUDE_CTX", default_value: include_ctx_dir}] ++ post_from_cmds

    %Container{target | commands: commands}
  end

  @spec write_containerfile([Arg.t()], Container.t(), Path.t()) :: :ok
  defp write_containerfile(args, %Container{} = target, path) do
    containerfile = Enum.map_join(args ++ target.commands, "\n", &Fmt.fmt(&1))
    File.write!(path, containerfile)

    :ok
  end

  @spec fq_targets_image_ref(Type.pipeline_uuid(), Cakefile.t()) :: Cakefile.t()
  defp fq_targets_image_ref(pipeline_uuid, %Cakefile{} = cakefile) do
    update_fn = fn "+" <> tgid -> container().fq_image(tgid, pipeline_uuid) end

    cakefile =
      update_in(
        cakefile,
        [
          Access.key!(:targets),
          Access.filter(&match?(%Container{}, &1)),
          Access.key!(:commands),
          Access.filter(&match?(%From{image: "+" <> _}, &1)),
          Access.key!(:image)
        ],
        update_fn
      )

    update_in(
      cakefile,
      [
        Access.key!(:targets),
        Access.filter(&match?(%Container{}, &1)),
        Access.key!(:commands),
        Access.filter(&match?(%Command{instruction: "COPY"}, &1)),
        Access.key!(:options),
        Access.filter(&match?(%Command.Option{name: "from"}, &1)),
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
