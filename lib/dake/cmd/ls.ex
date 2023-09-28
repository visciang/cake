defimpl Dake.Cmd, for: Dake.CliArgs.Ls do
  @moduledoc """
  ls Command.
  """

  alias Dake.CliArgs.Ls
  alias Dake.Dag
  alias Dake.Parser.Dakefile
  alias Dake.Parser.Docker.Arg
  alias Dake.Parser.Target
  alias Dake.Type

  @typep target_args :: %{Type.tgid() => [Arg.t()]}

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
        fn %_{tgid: tgid} -> tgid end
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
    |> Dag.tgids()
    |> Enum.sort()
    |> Enum.map(&fmt_target(&1, target_args))
    |> Enum.each(&IO.puts("  #{&1}"))

    :ok
  end

  @spec tree_alias(Dag.graph(), [Type.tgid()]) :: :ok
  defp tree_alias(graph, tgids) do
    Enum.each(tgids, fn tgid ->
      downstream_tgids =
        Dag.downstream_tgids(graph, tgid)
        |> Enum.sort()
        |> Enum.map_join(" ", &fmt_target(&1, %{}, false))

      IO.puts("""
        → #{fmt_target(tgid, %{})}
          #{downstream_tgids}\
      """)
    end)
  end

  @spec tree_docker(Dag.graph(), [Type.tgid()], target_args(), non_neg_integer()) :: :ok
  defp tree_docker(_graph, [], _target_args, _level), do: :ok

  defp tree_docker(graph, tgids, target_args, level) do
    tgids
    |> Enum.sort()
    |> Enum.each(fn tgid ->
      indent = String.duplicate(" ", level * 2)
      indent = if level == 1, do: "#{indent}", else: indent
      arrow = if level == 1, do: "→", else: "↳"
      target_args = if level == 1, do: target_args, else: %{}
      IO.puts("#{indent}#{arrow} #{fmt_target(tgid, target_args, level == 1)}")

      tree_docker(graph, Dag.downstream_tgids(graph, tgid), target_args, level + 1)
    end)
  end

  @spec target_args(Dakefile.t()) :: target_args()
  defp target_args(%Dakefile{} = dakefile) do
    dakefile.targets
    |> Enum.filter(&match?(%Target.Docker{}, &1))
    |> Map.new(fn %Target.Docker{} = docker ->
      {docker.tgid, Enum.filter(docker.commands, &match?(%Arg{}, &1))}
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

  @spec fmt_target(Type.tgid(), target_args(), color :: boolean()) :: IO.chardata()
  defp fmt_target(tgid, target_args, color \\ true) do
    args = Map.get(target_args, tgid, [])
    args = Enum.map_join(args, ", ", &fmt_arg(&1))

    if color do
      IO.ANSI.format([:green, tgid, :reset, "  ", args])
    else
      [tgid, " ", args]
    end
  end
end
