defimpl Dake.Cmd, for: Dake.CliArgs.Ls do
  @moduledoc """
  ls Command.
  """

  alias Dake.CliArgs.Ls
  alias Dake.Dag
  alias Dake.Parser.Dakefile
  alias Dake.Parser.Docker.Arg
  alias Dake.Parser.Target

  @typep target_args :: %{(target :: String.t()) => [Arg.t()]}

  @spec exec(Ls.t(), Dakefile.t(), Dag.graph()) :: :ok
  def exec(%Ls{tree: true}, %Dakefile{} = dakefile, graph) do
    global_args = dakefile.args
    target_args = target_args(dakefile)

    if global_args != [] do
      IO.puts(["  ", Enum.map_join(global_args, ", ", &fmt_arg(&1))])
    end

    %{Target.Alias => alias_targets, Target.Docker => docker_targets} =
      dakefile.targets
      |> Enum.group_by(
        fn %target_type{} -> target_type end,
        fn %_{target: target} -> target end
      )

    tree_alias(graph, alias_targets)
    tree_docker(graph, docker_targets, target_args, 1)
  end

  def exec(%Ls{}, %Dakefile{} = dakefile, graph) do
    global_args = dakefile.args
    target_args = target_args(dakefile)

    if global_args != [] do
      IO.puts(["  ", Enum.map_join(global_args, ", ", &fmt_arg(&1)), "\n"])
    end

    graph
    |> Dag.targets()
    |> Enum.sort()
    |> Enum.map(&fmt_target(&1, target_args))
    |> Enum.each(&IO.puts("  #{&1}"))

    :ok
  end

  @spec tree_alias(Dag.graph(), [target :: String.t()]) :: :ok
  defp tree_alias(graph, targets) do
    Enum.each(targets, fn target ->
      downstream_targets =
        Dag.downstream_targets(graph, target)
        |> Enum.sort()
        |> Enum.map_join(" ", &fmt_target(&1, %{}, false))

      IO.puts("""
        → #{fmt_target(target, %{})}
          #{downstream_targets}\
      """)
    end)
  end

  @spec tree_docker(Dag.graph(), [target :: String.t()], target_args(), non_neg_integer()) :: :ok
  defp tree_docker(_graph, [], _target_args, _level), do: :ok

  defp tree_docker(graph, targets, target_args, level) do
    targets
    |> Enum.sort()
    |> Enum.each(fn target ->
      indent = String.duplicate(" ", level * 2)
      indent = if level == 1, do: "#{indent}", else: indent
      arrow = if level == 1, do: "→", else: "↳"
      target_args = if level == 1, do: target_args, else: %{}
      IO.puts("#{indent}#{arrow} #{fmt_target(target, target_args, level == 1)}")

      tree_docker(graph, Dag.downstream_targets(graph, target), target_args, level + 1)
    end)
  end

  @spec target_args(Dakefile.t()) :: target_args()
  defp target_args(%Dakefile{} = dakefile) do
    dakefile.targets
    |> Enum.filter(&match?(%Target.Docker{}, &1))
    |> Map.new(fn %Target.Docker{} = docker ->
      {docker.target, Enum.filter(docker.commands, &match?(%Arg{}, &1))}
    end)
  end

  @spec fmt_arg(Arg.t()) :: String.t()
  defp fmt_arg(%Arg{} = arg) do
    if arg.default_value do
      "#{arg.name}=#{arg.default_value}"
    else
      arg.name
    end
  end

  @spec fmt_target(String.t(), target_args(), color :: boolean()) :: IO.chardata()
  defp fmt_target(target, target_args, color \\ true) do
    args = Map.get(target_args, target, [])
    args = Enum.map_join(args, ", ", &fmt_arg(&1))

    if color do
      IO.ANSI.format([:green, target, :reset, "  ", args])
    else
      [target, " ", args]
    end
  end
end
