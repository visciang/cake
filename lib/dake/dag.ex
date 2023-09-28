defmodule Dake.Dag do
  @moduledoc """
  Dakfile targets DAG.
  """

  defmodule Error do
    @moduledoc false
    defexception [:message]
  end

  alias Dake.Parser.{Dakefile, Docker, Target}
  alias Dake.Type

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
  Return the targets ids.
  """
  @spec tgids(graph()) :: [Type.tgid()]
  def tgids(graph) do
    :digraph.vertices(graph)
  end

  @doc """
  Return the downstream (dependant) targets of a specific target.
  """
  @spec downstream_tgids(graph(), Type.tgid()) :: [Type.tgid()]
  def downstream_tgids(graph, vertex) do
    :digraph.out_neighbours(graph, vertex)
  end

  @spec add_vertices(:digraph.graph(), Dakefile.t()) :: :ok
  defp add_vertices(graph, %Dakefile{} = dakefile) do
    Enum.each(dakefile.targets, fn
      %Target.Docker{tgid: tgid} ->
        :digraph.add_vertex(graph, tgid)

      %Target.Alias{tgid: tgid} ->
        :digraph.add_vertex(graph, tgid)
    end)

    :ok
  end

  @spec add_edges(:digraph.graph(), Dakefile.t()) :: :ok
  defp add_edges(graph, %Dakefile{} = dakefile) do
    Enum.each(dakefile.targets, fn
      %Target.Docker{tgid: downstream_tgid, commands: commands} ->
        add_command_edges(graph, commands, downstream_tgid)

      %Target.Alias{tgid: upstream_tgid, tgids: downstream_tgids} ->
        Enum.each(downstream_tgids, fn downstream_tgid ->
          add_edge(graph, upstream_tgid, downstream_tgid)
        end)
    end)

    :ok
  end

  @spec add_command_edges(:digraph.graph(), [Target.Docker.command()], Type.tgid()) :: :ok
  defp add_command_edges(graph, commands, downstream_tgid) do
    Enum.each(commands, fn
      %Docker.From{image: "+" <> upstream_tgid} ->
        add_edge(graph, upstream_tgid, downstream_tgid)

      %Docker.Command{instruction: "COPY", options: options} ->
        case Docker.Command.find_option(options, "from") do
          %Docker.Command.Option{value: "+" <> upstream_tgid} ->
            add_edge(graph, upstream_tgid, downstream_tgid)

          _ ->
            :ok
        end

      _ ->
        :ok
    end)
  end

  @spec add_edge(:digraph.graph(), Type.tgid(), Type.tgid()) :: :ok
  defp add_edge(graph, upstream_tgid, downstream_tgid) do
    case :digraph.add_edge(graph, upstream_tgid, downstream_tgid) do
      {:error, {:bad_edge, path}} ->
        cycle_path = Enum.map_join(path, " -> ", & &1.id)

        raise Error, "Targets cycle detected: #{cycle_path}"

      {:error, {:bad_vertex, tgid}} ->
        raise Error, "Unknown target: #{tgid}"

      _ ->
        :ok
    end
  end
end
