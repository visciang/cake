defmodule Dake.Dag do
  @moduledoc """
  Dakfile targets DAG.
  """

  defmodule Error do
    @moduledoc false
    defexception [:message]
  end

  alias Dake.Parser.{Dakefile, Docker, Target}

  @opaque graph :: :digraph.graph()
  @type result :: {:ok, graph()} | {:error, reason :: term()}

  @doc """
  Extract the targets DAG from a Dakefile
  """
  @spec extract(Dakefile.t()) :: result()
  def extract(%Dakefile{} = dakefile) do
    graph = :digraph.new([:acyclic])
    add_vertices(graph, dakefile)

    try do
      add_edges(graph, dakefile)

      {:ok, graph}
    rescue
      error in [Error] ->
        {:error, error.message}
    end
  end

  @doc """
  Return the targets.
  """
  @spec targets(graph()) :: [target :: String.t()]
  def targets(graph) do
    :digraph.vertices(graph)
  end

  @doc """
  Return the downstream (dependant) targets of a specific target.
  """
  @spec downstream_targets(graph(), target :: String.t()) :: [target :: String.t()]
  def downstream_targets(graph, vertex) do
    :digraph.out_neighbours(graph, vertex)
  end

  @spec add_vertices(:digraph.graph(), Dakefile.t()) :: :ok
  defp add_vertices(graph, %Dakefile{} = dakefile) do
    Enum.each(dakefile.targets, fn
      %Target.Docker{target: target} ->
        :digraph.add_vertex(graph, target)

      %Target.Alias{target: target} ->
        :digraph.add_vertex(graph, target)
    end)

    :ok
  end

  @spec add_edges(:digraph.graph(), Dakefile.t()) :: :ok
  defp add_edges(graph, %Dakefile{} = dakefile) do
    Enum.each(dakefile.targets, fn
      %Target.Docker{target: downstream_target, commands: commands} ->
        add_command_edges(graph, commands, downstream_target)

      %Target.Alias{target: upstream_target, targets: downstream_targets} ->
        Enum.each(downstream_targets, fn downstream_target ->
          add_edge(graph, upstream_target, downstream_target)
        end)
    end)

    :ok
  end

  @spec add_command_edges(:digraph.graph(), [Target.Docker.command()], String.t()) :: :ok
  defp add_command_edges(graph, commands, downstream_target) do
    Enum.each(commands, fn
      %Docker.From{image: "+" <> upstream_target} ->
        add_edge(graph, upstream_target, downstream_target)

      %Docker.Command{instruction: "COPY", options: options} ->
        case Docker.Command.find_option(options, "from") do
          %Docker.Command.Option{value: "+" <> upstream_target} ->
            add_edge(graph, upstream_target, downstream_target)

          _ ->
            :ok
        end

      _ ->
        :ok
    end)
  end

  @spec add_edge(:digraph.graph(), String.t(), String.t()) :: :ok
  defp add_edge(graph, upstream_target, downstream_target) do
    case :digraph.add_edge(graph, upstream_target, downstream_target) do
      {:error, {:bad_edge, path}} ->
        cycle_path = Enum.map_join(path, " -> ", & &1.id)

        raise Error, "Targets cycle detected: #{cycle_path}"

      {:error, {:bad_vertex, target}} ->
        raise Error, "Unknown target: #{target}"

      _ ->
        :ok
    end
  end
end
