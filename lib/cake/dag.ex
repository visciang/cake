defmodule Cake.Dag do
  defmodule Error do
    defexception [:message]
  end

  alias Cake.Parser.{Alias, Cakefile, Target}
  alias Cake.Parser.Container.{Command, From}
  alias Cake.Type

  @opaque graph :: :digraph.graph()
  @type result :: {:ok, graph()} | {:error, reason :: term()}

  @spec extract(Cakefile.t()) :: result()
  def extract(%Cakefile{} = cakefile) do
    graph = :digraph.new([:acyclic])
    add_vertices(graph, cakefile)

    try do
      add_edges(graph, cakefile)

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

  @spec add_vertices(:digraph.graph(), Cakefile.t()) :: :ok
  defp add_vertices(graph, %Cakefile{} = cakefile) do
    for target <- cakefile.targets do
      case target do
        %Target{tgid: tgid} -> :digraph.add_vertex(graph, tgid)
        %Alias{tgid: tgid} -> :digraph.add_vertex(graph, tgid)
      end
    end

    :ok
  end

  @spec add_edges(:digraph.graph(), Cakefile.t()) :: :ok
  defp add_edges(graph, %Cakefile{} = cakefile) do
    for target <- cakefile.targets do
      case target do
        %Target{tgid: downstream_tgid, commands: commands} ->
          add_command_edges(graph, commands, downstream_tgid)

        %Alias{tgid: downstream_tgid, tgids: upstream_tgids} ->
          for upstream_tgid <- upstream_tgids do
            add_edge(graph, upstream_tgid, downstream_tgid)
          end
      end
    end

    :ok
  end

  @spec add_command_edges(:digraph.graph(), [Target.command()], Type.tgid()) :: :ok
  defp add_command_edges(graph, commands, downstream_tgid) do
    for %From{image: "+" <> upstream_tgid} <- commands do
      add_edge(graph, upstream_tgid, downstream_tgid)
    end

    for %Command{instruction: "COPY", options: options} <- commands,
        %Command.Option{name: "from", value: "+" <> upstream_tgid} <- options do
      add_edge(graph, upstream_tgid, downstream_tgid)
    end

    :ok
  end

  @spec add_edge(:digraph.graph(), Type.tgid(), Type.tgid()) :: :ok
  defp add_edge(graph, upstream_tgid, downstream_tgid) do
    case :digraph.add_edge(graph, upstream_tgid, downstream_tgid) do
      {:error, {:bad_edge, path}} ->
        cycle_path = Enum.map_join(path, " -> ", & &1)

        raise Error, "Targets cycle detected: #{cycle_path}"

      {:error, {:bad_vertex, tgid}} ->
        raise Error, "Unknown target: #{tgid}"

      _ ->
        :ok
    end
  end
end
