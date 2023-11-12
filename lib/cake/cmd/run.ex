defimpl Cake.Cmd, for: Cake.Cli.Run do
  alias Cake.Cli.Run
  alias Cake.{Cmd, Dag, Pipeline, Reporter}
  alias Cake.Parser.Cakefile
  alias Dask.Limiter

  @spec exec(Run.t(), Cakefile.t(), Dag.graph()) :: Cmd.result()
  def exec(%Run{} = run, %Cakefile{} = cakefile, graph) do
    Reporter.verbose(run.verbose)
    Reporter.logs_to_file(run.save_logs)

    unless run.tgid in Dag.tgids(graph) do
      Cake.System.halt(:error, "Unknown target '#{run.tgid}'")
    end

    {:ok, limiter} = Limiter.start_link(run.parallelism)

    Pipeline.build(run, cakefile, graph)
    |> Dask.async(limiter)
    |> Dask.await(run.timeout)
    |> case do
      {:ok, _} -> :ok
      {:error, _} = error -> error
      :timeout -> :timeout
    end
  end
end
