defimpl Cake.Cmd, for: Cake.Cli.Run do
  alias Cake.Cli.Run
  alias Cake.{Cmd, Dag, Dir, Pipeline, Reporter, Type}
  alias Cake.Parser.{Cakefile, Target.Local}
  alias Cake.Reporter
  alias Dask.Limiter

  @spec exec(Run.t(), Cakefile.t(), Dag.graph()) :: Cmd.result()
  def exec(%Run{} = run, %Cakefile{} = cakefile, graph) do
    Dir.setup_cake_dirs()

    Reporter.start_link(run.progress, run.save_logs)

    with :ok <- check_target_exists(run, graph),
         :ok <- check_target_run_args(run, cakefile) do
      {:ok, limiter} = Limiter.start_link(run.parallelism)

      Pipeline.build(run, cakefile, graph)
      |> Dask.async(limiter)
      |> Dask.await(run.timeout)
      |> case do
        {:ok, _} -> {:ok, nil}
        {:error, _} = error -> error
        :timeout -> :timeout
      end
      |> tap(&Reporter.stop/1)
    end
  end

  @spec check_target_exists(Run.t(), Dag.graph()) :: :ok | {:error, msg :: String.t()}
  defp check_target_exists(%Run{} = run, graph) do
    tgids = Dag.tgids(graph)

    if run.tgid in tgids do
      :ok
    else
      maybe_tgid = did_you_mean(run.tgid, tgids)
      {:error, "Did you mean '#{maybe_tgid}'?'"}
    end
  end

  @spec check_target_run_args(Run.t(), Cakefile.t()) :: :ok | {:error, msg :: String.t()}
  defp check_target_run_args(%Run{} = run, %Cakefile{} = cakefile) do
    target = Enum.find(cakefile.targets, &(&1.tgid == run.tgid))

    case target do
      %Local{} when run.tag != nil ->
        {:error, "Option --tag is not allowed for LOCAL targets"}

      %Local{} when run.shell ->
        {:error, "Flag --shell is not allowed for LOCAL targets"}

      _ ->
        :ok
    end
  end

  @spec did_you_mean(Type.tgid(), [Type.tgid()]) :: Type.tgid() | nil
  defp did_you_mean(requested_tgid, available_tgids) do
    available_tgids
    |> Enum.sort_by(&String.jaro_distance(requested_tgid, &1), :desc)
    |> List.first()
  end
end
