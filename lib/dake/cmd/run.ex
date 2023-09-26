defimpl Dake.Cmd, for: Dake.CliArgs.Run do
  @moduledoc """
  run Command.
  """

  alias Dake.CliArgs.Run
  alias Dake.Dag
  alias Dake.Parser.{Dakefile, Docker, Target}
  alias Dake.Pipeline

  @spec exec(Run.t(), Dakefile.t(), Dag.graph()) :: :ok
  def exec(%Run{} = run, %Dakefile{} = dakefile, _graph) do
    dockerfile = Pipeline.build(dakefile, run.push)

    build_args = Enum.flat_map(run.args, fn {name, value} -> ["--build-arg", "#{name}=#{value}"] end)
    force_push_build_args = if run.push, do: push_targets_build_args(dakefile), else: []

    cmd_args =
      ["buildx", "build", "--file", dockerfile, "--target", run.target] ++ build_args ++ force_push_build_args ++ ["."]

    IO.puts(inspect(cmd_args))

    System.cmd("docker", cmd_args)

    :ok
  end

  @spec push_targets_build_args(Dakefile.t()) :: [String.t()]
  defp push_targets_build_args(%Dakefile{} = dakefile) do
    dakefile.targets
    |> Enum.filter(fn
      %Target.Docker{} = docker ->
        Enum.any?(docker.commands, &match?(%Docker.DakePush{}, &1))

      _ ->
        false
    end)
    |> Enum.flat_map(&["--build-arg", "#{String.upcase(&1.target)}=#{inspect(make_ref())}"])
  end
end
