defimpl Dake.Cmd, for: Dake.CliArgs.Run do
  alias Dake.CliArgs.Run
  alias Dake.{Cmd, Dag, Pipeline}
  alias Dake.Parser.Dakefile

  @spec exec(Run.t(), Dakefile.t(), Dag.graph()) :: Cmd.result()
  def exec(%Run{} = run, %Dakefile{} = dakefile, graph) do
    unless run.tgid in Dag.tgids(graph) do
      Dake.System.halt(:error, "Unknown target '#{run.tgid}'")
    end

    Pipeline.build(run, dakefile, graph)
    |> Dask.async(run.parallelism)
    |> Dask.await(run.timeout)
    |> case do
      {:ok, _} -> :ok
      {:error, _} = error -> error
      :timeout -> {:error, :timeout}
    end
  end
end
