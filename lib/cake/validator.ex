defmodule Cake.Validator do
  alias Cake.Dag
  alias Cake.Parser.{Alias, Cakefile, Container, Target}
  alias Cake.Parser.Directive.Push

  @type result() :: :ok | {:error, reason :: term()}

  @spec check(Cakefile.t(), Dag.graph()) :: result()
  def check(%Cakefile{} = cakefile, graph) do
    with :ok <- check_alias_targets(cakefile, graph),
         :ok <- check_push_targets(cakefile, graph),
         :ok <- check_from(cakefile, graph) do
      :ok
    end
  end

  @spec check_alias_targets(Cakefile.t(), Dag.graph()) :: result()
  defp check_alias_targets(%Cakefile{} = cakefile, _graph) do
    alias_tgids =
      for %Alias{tgid: tgid} <- cakefile.targets,
          into: MapSet.new(),
          do: tgid

    all_commands =
      for %Target{commands: commands} <- cakefile.targets,
          command <- commands,
          do: command

    tgids_referenced_in_from =
      for %Container.From{image: image} <- all_commands,
          do: image

    tgids_referenced_in_copy =
      for %Container.Command{instruction: "COPY", options: options} <- all_commands,
          %Container.Command.Option{name: "from", value: value} <- options,
          do: value

    tgids_referenced =
      for "+" <> ref <- tgids_referenced_in_from ++ tgids_referenced_in_copy,
          into: MapSet.new(),
          do: ref

    bad_tgids = MapSet.intersection(alias_tgids, tgids_referenced)

    if MapSet.size(bad_tgids) == 0 do
      :ok
    else
      bad_tgids = Enum.to_list(bad_tgids)
      {:error, "alias targets #{inspect(bad_tgids)} cannot be referenced in FROM/COPY instructions"}
    end
  end

  @spec check_push_targets(Cakefile.t(), Dag.graph()) :: result()
  defp check_push_targets(%Cakefile{} = cakefile, graph) do
    push_targets =
      for %Target{directives: directives} = target <- cakefile.targets,
          Enum.any?(directives, &match?(%Push{}, &1)),
          do: target

    bad_targets = Enum.filter(push_targets, &(Dag.downstream_tgids(graph, &1.tgid) != []))

    if bad_targets == [] do
      :ok
    else
      bad_tgids = for bad_target <- bad_targets, do: bad_target.tgid
      {:error, "push targets #{inspect(bad_tgids)} can be only terminal target"}
    end
  end

  @spec check_from(Cakefile.t(), Dag.graph()) :: result()
  defp check_from(%Cakefile{} = cakefile, _graph) do
    cakefile.targets
    |> Enum.filter(&match?(%Target{commands: [_ | _]}, &1))
    |> Enum.reduce_while(:ok, fn
      %Target{tgid: tgid, commands: commands}, :ok ->
        case commands do
          [%Container.From{as: as} | _] when as != nil ->
            {:halt, {:error, "'FROM .. AS ..' form is not allowed, please remove the AS argument under #{tgid}"}}

          [%Container.From{} | _] ->
            {:cont, :ok}

          _ ->
            {:halt, {:error, "#{tgid} doesn't start with a FROM command"}}
        end
    end)
  end
end
