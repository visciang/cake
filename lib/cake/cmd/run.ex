defimpl Cake.Cmd, for: Cake.Cli.Run do
  alias Cake.Cli.Run
  alias Cake.{Cmd, Dag, Dir, Pipeline, Reporter, Type}
  alias Cake.Parser.Cakefile
  alias Cake.Reporter
  alias Dask.Limiter

  @spec exec(Run.t(), Cakefile.t(), Dag.graph()) :: Cmd.result()
  def exec(%Run{} = run, %Cakefile{} = cakefile, graph) do
    Dir.setup_cake_dirs()

    Reporter.start_link(run.progress, run.save_logs)

    tgids = Dag.tgids(graph)

    # coveralls-ignore-start

    unless run.tgid in tgids do
      maybe_tgid = did_you_mean(run.tgid, tgids)
      Cake.System.halt(:error, "Did you mean '#{maybe_tgid}'?'")
    end

    # coveralls-ignore-stop

    {:ok, limiter} = Limiter.start_link(run.parallelism)

    res =
      Pipeline.build(run, cakefile, graph)
      |> Dask.async(limiter)
      |> Dask.await(run.timeout)
      |> case do
        {:ok, _} -> :ok
        {:error, _} = error -> error
        :timeout -> :timeout
      end

    Reporter.stop(res)

    res
  end

  # coveralls-ignore-start

  @spec did_you_mean(Type.tgid(), [Type.tgid()]) :: Type.tgid() | nil
  defp did_you_mean(requested_tgid, available_tgids) do
    available_tgids
    |> Enum.sort_by(&String.jaro_distance(requested_tgid, &1), :desc)
    |> List.first()
  end

  # coveralls-ignore-stop
end
