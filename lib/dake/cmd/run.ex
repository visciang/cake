defimpl Dake.Cmd, for: Dake.Cli.Run do
  alias Dake.Cli.Run
  alias Dake.{Cmd, Dag, Pipeline, Reporter}
  alias Dake.Parser.Dakefile
  alias Dask.Limiter

  @spec exec(Run.t(), Dakefile.t(), Dag.graph()) :: Cmd.result()
  def exec(%Run{} = run, %Dakefile{} = dakefile, graph) do
    Reporter.logs(run.verbose)
    Reporter.logs_to_file(run.save_logs)

    unless run.tgid in Dag.tgids(graph) do
      Dake.System.halt(:error, "Unknown target '#{run.tgid}'")
    end

    limiter = start_global_limiter(run)

    Pipeline.build(run, dakefile, graph)
    |> Dask.async(limiter)
    |> Dask.await(run.timeout)
    |> case do
      {:ok, _} -> :ok
      {:error, _} = error -> error
      :timeout -> :timeout
    end
  end

  @spec start_global_limiter(Run.t()) :: GenServer.name()
  defp start_global_limiter(%Run{} = run) do
    limiter_name = :dask_global_limiter

    case Limiter.start_link(run.parallelism, limiter_name) do
      {:error, {:already_started, _}} -> :ok
      {:ok, _} -> :ok
    end

    limiter_name
  end
end
