defmodule Cake.Validator do
  alias Cake.Dag
  alias Cake.Parser.{Cakefile, Container, Directive, Target}

  @type result() :: :ok | {:error, reason :: term()}

  @spec check(Cakefile.t(), Dag.graph()) :: result()
  def check(%Cakefile{} = cakefile, graph) do
    with :ok <- check_alias_targets(cakefile, graph),
         :ok <- check_push_targets(cakefile, graph),
         :ok <- check_compose_run(cakefile, graph),
         :ok <- check_from(cakefile, graph) do
      :ok
    end
  end

  @spec check_alias_targets(Cakefile.t(), Dag.graph()) :: result()
  defp check_alias_targets(%Cakefile{} = cakefile, _graph) do
    alias_tgids =
      cakefile.targets
      |> Enum.filter(&match?(%Target.Alias{}, &1))
      |> MapSet.new(& &1.tgid)

    all_commands =
      cakefile.targets
      |> Enum.filter(&match?(%Target.Container{}, &1))
      |> Enum.flat_map(& &1.commands)

    tgids_referenced_in_from =
      all_commands
      |> Enum.filter(&match?(%Container.From{}, &1))
      |> Enum.map(& &1.image)

    tgids_referenced_in_copy =
      all_commands
      |> get_in([
        Access.filter(&match?(%Container.Command{instruction: "COPY"}, &1)),
        Access.key!(:options),
        Access.filter(&match?(%Container.Command.Option{name: "from"}, &1)),
        Access.key!(:value)
      ])
      |> List.flatten()

    tgids_referenced =
      (tgids_referenced_in_from ++ tgids_referenced_in_copy)
      |> Enum.filter(&String.starts_with?(&1, "+"))
      |> Enum.map(&String.trim_leading(&1, "+"))
      |> MapSet.new()

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
      Enum.filter(cakefile.targets, fn
        %Target.Container{} = container ->
          Enum.any?(container.directives, &match?(%Directive.Push{}, &1))

        _ ->
          false
      end)

    bad_targets = Enum.filter(push_targets, &(Dag.downstream_tgids(graph, &1.tgid) != []))

    if bad_targets == [] do
      :ok
    else
      bad_tgids = Enum.map(bad_targets, & &1.tgid)
      {:error, "push targets #{inspect(bad_tgids)} can be only terminal target"}
    end
  end

  @spec check_from(Cakefile.t(), Dag.graph()) :: result()
  defp check_from(%Cakefile{} = cakefile, _graph) do
    cakefile.targets
    |> Enum.filter(&match?(%Target.Container{}, &1))
    |> Enum.reduce_while(:ok, fn
      %Target.Container{tgid: tgid, commands: commands}, :ok when commands != [] ->
        case commands do
          [%Container.From{as: as} | _] when as != nil ->
            reason = "'FROM .. AS ..' form is not allowed, please remove the AS argument under #{tgid}"
            {:halt, {:error, reason}}

          [%Container.From{} | _] ->
            {:cont, :ok}

          _ ->
            {:halt, {:error, "#{tgid} doesn't start with a FROM command"}}
        end

      _, :ok ->
        {:cont, :ok}
    end)
  end

  @spec check_compose_run(Cakefile.t(), Dag.graph()) :: result()
  defp check_compose_run(%Cakefile{} = cakefile, _graph) do
    cakefile.targets
    |> Enum.filter(&match?(%Target.Container{}, &1))
    |> Enum.reduce_while(:ok, fn
      %Target.Container{tgid: tgid, directives: directives, commands: []}, :ok ->
        if Enum.any?(directives, &match?(%Directive.ComposeRun{}, &1)) do
          {:cont, :ok}
        else
          {:halt, {:error, "#{tgid} doesn't start with a FROM command"}}
        end

      _, :ok ->
        {:cont, :ok}
    end)
  end
end
