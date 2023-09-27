defmodule Dake.Validator do
  @moduledoc """
  Dakefile Validator.
  """

  alias Dake.Dag
  alias Dake.Parser.{Dakefile, Docker, Target}

  @type result() :: :ok | {:error, reason :: term()}

  @spec check(Dakefile.t(), Dag.graph()) :: result()
  def check(%Dakefile{} = dakefile, graph) do
    with :ok <- check_alias_targets(dakefile, graph),
         :ok <- check_push_targets(dakefile, graph),
         :ok <- check_from(dakefile, graph) do
      :ok
    end
  end

  @spec check_alias_targets(Dakefile.t(), Dag.graph()) :: result()
  defp check_alias_targets(%Dakefile{} = dakefile, _graph) do
    alias_targets =
      dakefile.targets
      |> Enum.filter(&match?(%Target.Alias{}, &1))
      |> MapSet.new(& &1.target)

    all_commands =
      dakefile.targets
      |> Enum.filter(&match?(%Target.Docker{}, &1))
      |> Enum.flat_map(& &1.commands)

    targets_referenced_in_from =
      all_commands
      |> Enum.filter(&match?(%Docker.From{}, &1))
      |> Enum.map(& &1.image)

    targets_referenced_in_copy =
      all_commands
      |> Enum.reduce([], fn
        %Docker.Command{instruction: "COPY", options: options}, acc ->
          case Docker.Command.find_option(options, "from") do
            %Docker.Command.Option{value: value} ->
              [value | acc]

            nil ->
              acc
          end

        _, acc ->
          acc
      end)

    targets_referenced =
      (targets_referenced_in_from ++ targets_referenced_in_copy)
      |> Enum.filter(&String.starts_with?(&1, "+"))
      |> Enum.map(&String.trim_leading(&1, "+"))
      |> MapSet.new()

    bad_targets =
      MapSet.intersection(alias_targets, targets_referenced)

    if MapSet.size(bad_targets) == 0 do
      :ok
    else
      bad_targets = Enum.to_list(bad_targets)
      {:error, "alias targets #{inspect(bad_targets)} cannot be referenced in FROM/COPY instructions"}
    end
  end

  @spec check_push_targets(Dakefile.t(), Dag.graph()) :: result()
  defp check_push_targets(%Dakefile{} = dakefile, graph) do
    push_targets =
      Enum.filter(dakefile.targets, fn
        %Target.Docker{} = docker ->
          Enum.any?(docker.commands, &match?(%Docker.DakePush{}, &1))

        _ ->
          false
      end)

    bad_targets = Enum.filter(push_targets, &(Dag.downstream_targets(graph, &1.target) != []))

    if bad_targets == [] do
      :ok
    else
      targets = Enum.map(bad_targets, & &1.target)
      {:error, "push targets #{inspect(targets)} can be only terminal target"}
    end
  end

  @spec check_from(Dakefile.t(), Dag.graph()) :: result()
  defp check_from(%Dakefile{} = dakefile, _graph) do
    dakefile.targets
    |> Enum.filter(&match?(%Target.Docker{}, &1))
    |> Enum.reduce_while(:ok, fn %Target.Docker{target: target, commands: commands}, :ok ->
      case commands do
        [%Docker.From{as: as} | _] when as != nil ->
          {:halt, {:error, "'FROM .. AS ..' form is not allowed, please remove the AS argument under #{target}"}}

        [%Docker.From{} | _] ->
          {:cont, :ok}

        _ ->
          {:halt, {:error, "#{target} doesn't start with a FROM command"}}
      end
    end)
  end
end
