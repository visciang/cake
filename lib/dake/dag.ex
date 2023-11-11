defmodule Dake.Dag do
  defmodule Error do
    defexception [:message]
  end

  alias Dake.Parser.{Container, Dakefile, Target}
  alias Dake.Type

  @opaque graph :: :digraph.graph()
  @type result :: {:ok, graph()} | {:error, reason :: term()}

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

  @spec tgids(graph()) :: [Type.tgid()]
  def tgids(graph) do
    :digraph.vertices(graph)
  end

  @spec downstream_tgids(graph(), Type.tgid()) :: [Type.tgid()]
  def downstream_tgids(graph, vertex) do
    :digraph.out_neighbours(graph, vertex)
  end

  @spec upstream_tgids(graph(), Type.tgid()) :: [Type.tgid()]
  def upstream_tgids(graph, vertex) do
    :digraph.in_neighbours(graph, vertex)
  end

  @spec reaching_tgids(graph(), Type.tgid()) :: [Type.tgid()]
  def reaching_tgids(graph, tgid) do
    :digraph_utils.reaching([tgid], graph)
  end

  @spec add_vertices(:digraph.graph(), Dakefile.t()) :: :ok
  defp add_vertices(graph, %Dakefile{} = dakefile) do
    Enum.each(dakefile.targets, fn
      %Target.Container{tgid: tgid} ->
        :digraph.add_vertex(graph, tgid)

      %Target.Alias{tgid: tgid} ->
        :digraph.add_vertex(graph, tgid)
    end)

    :ok
  end

  @spec add_edges(:digraph.graph(), Dakefile.t()) :: :ok
  defp add_edges(graph, %Dakefile{} = dakefile) do
    Enum.each(dakefile.targets, fn
      %Target.Container{tgid: downstream_tgid, commands: commands} ->
        add_command_edges(graph, commands, downstream_tgid)

      %Target.Alias{tgid: downstream_tgid, tgids: upstream_tgids} ->
        Enum.each(upstream_tgids, fn upstream_tgid ->
          add_edge(graph, upstream_tgid, downstream_tgid)
        end)
    end)

    :ok
  end

  @spec add_command_edges(:digraph.graph(), [Target.Container.command()], Type.tgid()) :: :ok
  defp add_command_edges(graph, commands, downstream_tgid) do
    commands
    |> Enum.filter(&match?(%Container.From{image: "+" <> _}, &1))
    |> Enum.each(fn %Container.From{image: "+" <> upstream_tgid} ->
      add_edge(graph, upstream_tgid, downstream_tgid)
    end)

    commands
    |> get_in([
      Access.filter(&match?(%Container.Command{instruction: "COPY"}, &1)),
      Access.key!(:options),
      Access.filter(&match?(%Container.Command.Option{name: "from"}, &1)),
      Access.key!(:value)
    ])
    |> List.flatten()
    |> Enum.each(fn "+" <> upstream_tgid ->
      add_edge(graph, upstream_tgid, downstream_tgid)
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
