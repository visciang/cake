defimpl Dake.Cmd, for: Dake.CliArgs.Run do
  @moduledoc """
  run Command.
  """

  alias Dake.CliArgs.Run
  alias Dake.Dag
  alias Dake.Parser.Dakefile
  alias Dake.Pipeline

  @spec exec(Run.t(), Dakefile.t(), Dag.graph()) :: :ok
  def exec(%Run{} = run, %Dakefile{} = dakefile, _graph) do
    dockerfile = Pipeline.build(dakefile, run.push)

    build_args = Enum.flat_map(run.args, fn {name, value} -> ["--build-arg", "#{name}=#{value}"] end)
    docker_args = ["buildx", "build", "--file", dockerfile, "--target", run.target] ++ build_args ++ ["."]

    System.cmd("docker", docker_args)

    :ok
  end
end
