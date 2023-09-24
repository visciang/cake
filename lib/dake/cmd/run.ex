defmodule Dake.Cmd.Run do
  @moduledoc """
  run Command.
  """

  alias Dake.Dag
  alias Dake.Parser.Dakefile
  alias Dake.Pipeline

  @spec exec(Dakefile.t(), Dag.graph(), target :: String.t(), args :: [{String.t(), String.t()}]) :: :ok
  def exec(dakefile, _graph, target, args) do
    dockerfile = Pipeline.build(dakefile)

    build_args = Enum.flat_map(args, fn {name, value} -> ["--build-arg", "#{name}=#{value}"] end)

    docker_args =
      [
        "buildx",
        "build",
        "--progress",
        "plain",
        "--file",
        dockerfile,
        "--target",
        target
      ] ++
        build_args ++
        ["."]

    System.cmd("docker", docker_args)

    :ok
  end
end
