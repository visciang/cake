defmodule Cake.Validator do
  alias Cake.Dag
  alias Cake.Parser.Cakefile
  alias Cake.Parser.Directive.Push
  alias Cake.Parser.Target.{Alias, Container, Local}

  @type result() :: :ok | {:error, reason :: term()}

  @spec check(Cakefile.t(), Dag.graph()) :: result()
  def check(%Cakefile{} = cakefile, graph) do
    with :ok <- check_targets_references(cakefile, graph),
         :ok <- check_push_targets(cakefile, graph),
         :ok <- check_from(cakefile, graph) do
      :ok
    end
  end

  @spec check_targets_references(Cakefile.t(), Dag.graph()) :: result()
  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  defp check_targets_references(%Cakefile{} = cakefile, _graph) do
    alias_tgids =
      for %Alias{tgid: tgid} <- cakefile.targets,
          into: MapSet.new(),
          do: tgid

    local_tgids =
      for %Local{tgid: tgid} <- cakefile.targets,
          into: MapSet.new(),
          do: tgid

    all_commands =
      for %Container{commands: commands} <- cakefile.targets,
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

    bad_alias_tgids = MapSet.intersection(alias_tgids, tgids_referenced)
    bad_local_tgids = MapSet.intersection(local_tgids, tgids_referenced)

    cond do
      MapSet.size(bad_alias_tgids) != 0 ->
        bad_alias_tgids = Enum.to_list(bad_alias_tgids)
        {:error, "alias targets #{inspect(bad_alias_tgids)} cannot be referenced in FROM/COPY instructions"}

      MapSet.size(bad_local_tgids) != 0 ->
        bad_local_tgids = Enum.to_list(bad_local_tgids)
        {:error, "local targets #{inspect(bad_local_tgids)} cannot be referenced in FROM/COPY instructions"}

      true ->
        :ok
    end
  end

  @spec check_push_targets(Cakefile.t(), Dag.graph()) :: result()
  defp check_push_targets(%Cakefile{} = cakefile, graph) do
    push_targets =
      for %Container{directives: directives} = target <- cakefile.targets,
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
    |> Enum.filter(&match?(%Container{commands: [_ | _]}, &1))
    |> Enum.reduce([], fn
      %Container{tgid: tgid, commands: commands}, errors ->
        case commands do
          [%Container.From{as: as} | _] when as != nil ->
            ["'FROM .. AS ..' form is not allowed, please remove the AS argument under #{tgid}" | errors]

          [%Container.From{} | _] ->
            errors
        end
    end)
    |> case do
      [] -> :ok
      errors -> {:error, errors}
    end
  end
end
