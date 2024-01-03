defmodule Cake.Pipeline.Error do
  defexception [:message]
end

defmodule Cake.Pipeline do
  alias Cake.Cli.Run
  alias Cake.Parser.Container.{Arg, Command, Fmt, From}
  alias Cake.Parser.{Alias, Cakefile, Directive, Target}
  alias Cake.Pipeline.Container
  alias Cake.{Dag, Dir, Reference, Reporter, Type}

  require Cake.Reporter.Status
  require Logger

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
      Reporter.job_start(run.ns, tgid)

      case target do
        %Alias{} ->
          :ok

        %Target{} = target ->
          dask_job(run, cakefile, target, tgid, pipeline_uuid)
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

  @spec dask_job(Run.t(), Cakefile.t(), Target.t(), Type.tgid(), Type.pipeline_uuid()) :: :ok
  defp dask_job(%Run{} = run, %Cakefile{} = cakefile, %Target{} = target, tgid, pipeline_uuid) do
    Logger.info("start for #{inspect(tgid)}", pipeline: pipeline_uuid)

    dask_job_target_imports(run, target, pipeline_uuid)

    job_uuid = to_string(System.unique_integer([:positive]))
    container_build_ctx_dir = Path.dirname(cakefile.path)

    build_relative_include_ctx_dir =
      if target.included_from_ref do
        include_ctx_dir = Dir.local_include_ctx_dir(cakefile.path, target.included_from_ref)
        Path.relative_to(include_ctx_dir, container_build_ctx_dir)
      else
        ""
      end

    cakefile = insert_builtin_global_args(cakefile, pipeline_uuid)
    target = insert_builtin_container_args(target, build_relative_include_ctx_dir)

    containerfile_path = Path.join(Dir.tmp(), "#{job_uuid}-#{tgid}.Dockerfile")
    write_containerfile(cakefile.args, target, containerfile_path)

    push? = push_target?(target)
    args = container_build_cmd_args(run, containerfile_path, tgid, push?, pipeline_uuid, container_build_ctx_dir)

    Container.build(run, tgid, args, pipeline_uuid)

    if run.shell and tgid == run.tgid do
      Reporter.job_notice(run.ns, run.tgid, "\nStarting interactive shell:\n")
      Container.shell(tgid, pipeline_uuid)
    end

    if run.output do
      output_paths = for %Directive.Output{path: path} <- target.directives, do: path
      Container.output(run, tgid, pipeline_uuid, output_paths)
    end

    :ok
  end

  @spec dask_job_target_imports(Run.t(), Target.t(), Type.pipeline_uuid()) :: :ok
  defp dask_job_target_imports(%Run{} = run, %Target{} = target, pipeline_uuid) do
    for %Directive.Import{} = import_ <- target.directives do
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

      run = run_for_import(run, target, pipeline_uuid, import_)

      case Cake.cmd(run, import_.ref) do
        :ok ->
          :ok

        {:error, reason} ->
          raise Cake.Pipeline.Error, "failed @import #{inspect(import_.ref)} build: #{inspect(reason)}"

        :timeout ->
          raise Cake.Pipeline.Error, "timeout"
      end
    end

    :ok
  end

  @spec dask_job_target_imports(Run.t(), Target.t(), Type.pipeline_uuid()) :: Run.t()
  defp run_for_import(run, target, pipeline_uuid, import_) do
    %Run{
      ns: run.ns ++ [target.tgid],
      tgid: import_.target,
      args: for(arg <- import_.args, do: {arg.name, arg.default_value}),
      push: import_.push and run.push,
      output: import_.output and run.output,
      output_dir: import_.as,
      tag: Container.fq_image(import_.as, pipeline_uuid),
      timeout: :infinity,
      parallelism: run.parallelism,
      progress: run.progress,
      save_logs: run.save_logs,
      shell: false,
      secrets: run.secrets
    }
  end

  @spec build_dask_job_cleanup(Dask.t(), Dask.Job.id(), Type.pipeline_uuid()) :: Dask.t()
  defp build_dask_job_cleanup(dask, cleanup_job_id, pipeline_uuid) do
    job_passthrough_fn = fn _, _ ->
      :ok
    end

    job_on_exit_fn = fn _, _, _ ->
      Container.cleanup(pipeline_uuid)
    end

    Dask.job(dask, cleanup_job_id, job_passthrough_fn, :infinity, job_on_exit_fn)
  end

  @spec container_build_cmd_args(Run.t(), Path.t(), Type.tgid(), boolean(), Type.pipeline_uuid(), Path.t()) ::
          [String.t()]
  defp container_build_cmd_args(%Run{} = run, containerfile_path, tgid, push_target?, pipeline_uuid, build_ctx) do
    Enum.concat([
      ["--progress", "plain"],
      ["--file", containerfile_path],
      if(run.push and push_target?, do: ["--no-cache"], else: []),
      ["--tag", Container.fq_image(tgid, pipeline_uuid)],
      if(tgid == run.tgid and run.tag, do: ["--tag", run.tag], else: []),
      Enum.flat_map(run.args, fn {name, value} -> ["--build-arg", "#{name}=#{value}"] end),
      Enum.flat_map(run.secrets, fn secret -> ["--secret", secret] end),
      [build_ctx]
    ])
  end

  @spec push_target?(Cakefile.target()) :: boolean()
  defp push_target?(target) do
    case target do
      %Target{} -> Enum.any?(target.directives, &match?(%Directive.Push{}, &1))
      _ -> false
    end
  end

  @spec validate_cmd(Run.t(), Cakefile.target()) :: :ok | no_return()
  defp validate_cmd(%Run{} = run, target) do
    if not run.push and push_target?(target) do
      Cake.System.halt(:error, "@push target #{run.tgid} can be executed only via 'run --push'")
    end

    if run.shell and match?(%Alias{}, target) do
      Cake.System.halt(:error, "cannot shell into and \"alias\" target")
    end

    :ok
  end

  @spec insert_builtin_global_args(Cakefile.t(), Type.pipeline_uuid()) :: Cakefile.t()
  defp insert_builtin_global_args(%Cakefile{} = cakefile, pipeline_uuid) do
    %Cakefile{
      cakefile
      | args: cakefile.args ++ [%Arg{name: "CAKE_PIPELINE_UUID", default_value: pipeline_uuid}]
    }
  end

  @spec insert_builtin_container_args(Target.t(), Path.t()) :: Target.t()
  defp insert_builtin_container_args(%Target{} = target, include_ctx_dir) do
    from_idx = Enum.find_index(target.commands, &match?(%From{}, &1))
    {pre_from_cmds, [%From{} = from | post_from_cmds]} = Enum.split(target.commands, from_idx)

    commands =
      pre_from_cmds ++
        [from, %Arg{name: "CAKE_INCLUDE_CTX", default_value: include_ctx_dir}] ++ post_from_cmds

    %Target{target | commands: commands}
  end

  @spec write_containerfile([Arg.t()], Target.t(), Path.t()) :: :ok
  defp write_containerfile(args, %Target{} = target, path) do
    containerfile = Enum.map_join(args ++ target.commands, "\n", &Fmt.fmt(&1))
    File.write!(path, containerfile)

    :ok
  end

  @spec fq_targets_image_ref(Type.pipeline_uuid(), Cakefile.t()) :: Cakefile.t()
  defp fq_targets_image_ref(pipeline_uuid, %Cakefile{} = cakefile) do
    update_fn = fn "+" <> tgid -> Container.fq_image(tgid, pipeline_uuid) end

    cakefile =
      update_in(
        cakefile,
        [
          Access.key!(:targets),
          Access.filter(&match?(%Target{}, &1)),
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
        Access.filter(&match?(%Target{}, &1)),
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
