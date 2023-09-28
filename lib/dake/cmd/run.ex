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

    build_args = build_args(run.args)
    force_push_build_args = if run.push, do: push_targets_build_args(dakefile), else: []

    cmd_args =
      ["buildx", "build", "--file", dockerfile, "--target", run.tgid] ++ build_args ++ force_push_build_args ++ ["."]

    System.cmd("docker", cmd_args)

    :ok
  end

  @spec push_targets_build_args(Dakefile.t()) :: [String.t()]
  defp push_targets_build_args(%Dakefile{} = dakefile) do
    dakefile.targets
    |> Enum.filter(fn target ->
      match?(%Target.Docker{}, target) and Enum.any?(target.commands, &match?(%Docker.DakePush{}, &1))
    end)
    |> Enum.map(&{String.upcase(&1.tgid), inspect(make_ref())})
    |> build_args()
  end

  @spec build_args([{String.t(), String.t()}]) :: [String.t()]
  defp build_args(args) do
    Enum.flat_map(args, fn {name, value} -> ["--build-arg", "#{name}=#{value}"] end)
  end
end
