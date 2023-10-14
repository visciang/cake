defimpl Dake.Cmd, for: Dake.Cli.Run do
  alias Dake.Cli.Run
  alias Dake.{Cmd, Dag, Pipeline, Reporter}
  alias Dake.Parser.Dakefile

  @spec exec(Run.t(), Dakefile.t(), Dag.graph()) :: Cmd.result()
  def exec(%Run{} = run, %Dakefile{} = dakefile, graph) do
    Reporter.logs(run.verbose)
    Reporter.logs_to_file(run.save_logs)

    unless run.tgid in Dag.tgids(graph) do
      Dake.System.halt(:error, "Unknown target '#{run.tgid}'")
    end

    Pipeline.build(run, dakefile, graph)
    |> Dask.async(run.parallelism)
    |> Dask.await(run.timeout)
    |> case do
      {:ok, _} -> :ok
      {:error, _} = error -> error
      :timeout -> :timeout
    end
  end
end
