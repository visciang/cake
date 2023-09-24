defmodule Dake.Cmd.Ls do
  @moduledoc """
  ls Command.
  """

  alias Dake.Dag
  alias Dake.Parser.Dakefile
  alias Dake.Parser.Target

  @spec list(Dakefile.t(), Dag.graph()) :: :ok
  def list(_dakefile, graph) do
    IO.puts("\nAvailable targets:\n")

    graph
    |> Dag.targets()
    |> Enum.sort()
    |> Enum.map(&fmt_target/1)
    |> Enum.each(&IO.puts("  #{&1}"))

    :ok
  end

  @spec tree(Dakefile.t(), Dag.graph()) :: :ok
  def tree(dakefile, graph) do
    IO.puts("\nAvailable targets:\n")

    %{Target.Alias => alias_targets, Target.Docker => docker_targets} =
      dakefile.targets
      |> Enum.group_by(
        fn %target_type{} -> target_type end,
        fn %_{target: target} -> target end
      )

    tree_alias(graph, alias_targets)
    tree_docker(graph, docker_targets, 1)
  end

  @spec tree_alias(Dag.graph(), [target :: String.t()]) :: :ok
  defp tree_alias(graph, targets) do
    Enum.each(targets, fn target ->
      downstream_targets =
        Dag.downstream_targets(graph, target)
        |> Enum.sort()
        |> Enum.map_join(" ", &fmt_target(&1, false))

      IO.puts("""
        → #{fmt_target(target)}
          #{downstream_targets}\
      """)
    end)
  end

  @spec tree_docker(Dag.graph(), [target :: String.t()], non_neg_integer()) :: :ok
  defp tree_docker(_graph, [], _level), do: :ok

  defp tree_docker(graph, targets, level) do
    targets
    |> Enum.sort()
    |> Enum.each(fn target ->
      indent = String.duplicate(" ", level * 2)
      indent = if level == 1, do: "#{indent}", else: indent
      arrow = if level == 1, do: "→", else: "↳"
      IO.puts("#{indent}#{arrow} #{fmt_target(target, level == 1)}")

      tree_docker(graph, Dag.downstream_targets(graph, target), level + 1)
    end)
  end

  @spec fmt_target(String.t(), color :: boolean()) :: String.t()
  defp fmt_target(target, color \\ true) do
    if color do
      IO.ANSI.format([:green, target])
    else
      target
    end
  end
end
