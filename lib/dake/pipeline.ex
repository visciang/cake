defmodule Dake.Pipeline do
  @moduledoc """
  Pipeline builder.
  """

  alias Dake.Parser.Dakefile
  alias Dake.Parser.Docker
  alias Dake.Parser.Target

  @dake_done_path "/.dake_done"
  @dake_ouput_path "/.dake_output"

  @typep pipeline_target :: {target :: String.t(), [Docker.Command.t()]}

  @spec build(Dakefile.t()) :: :ok
  def build(%Dakefile{} = dakefile) do
    pipeline_args = pipeline_args(dakefile.args)

    pipeline_docker_targets =
      dakefile.targets
      |> Enum.filter(&match?(%Target.Docker{}, &1))
      |> pipeline_targets()
      |> pipeline_add_default_target()
      |> pipeline_add_targets_done()

    pipeline_alias_targets =
      dakefile.targets
      |> Enum.filter(&match?(%Target.Alias{}, &1))
      |> pipeline_aliases()
      |> pipeline_add_targets_done()

    IO.puts("""
    # ==== pipeline ARGs ====

    #{fmt_pipeline_args(pipeline_args)}

    # ==== pipeline targets ====

    #{fmt_done_target()}
    #{fmt_pipeline_targets(pipeline_docker_targets)}

    # ==== pipeline aliases ====

    #{fmt_pipeline_targets(pipeline_alias_targets)}
    """)

    :ok
  end

  @spec pipeline_args([Docker.Arg.t()]) :: [Docker.Arg.t()]
  defp pipeline_args(args), do: args

  @spec pipeline_aliases([Target.Alias.t()]) :: [pipeline_target()]
  defp pipeline_aliases(aliases) do
    Enum.map(aliases, fn %Target.Alias{} = alias_ ->
      commands = Enum.map(alias_.targets, fn target -> command_copy_done(target) end)

      commands = [
        %Docker.Command{instruction: "FROM", arguments: "scratch AS #{alias_.target}"}
        | commands
      ]

      {alias_.target, commands}
    end)
  end

  @spec pipeline_target_output(Target.Docker.t()) :: pipeline_target()
  defp pipeline_target_output(%Target.Docker{} = docker) do
    commands = [
      %Docker.Command{instruction: "FROM", arguments: "scratch AS #{t_output(docker.target)}"},
      command_copy_done(docker.target)
    ]

    commands =
      if Enum.any?(docker.commands, &match?(%Docker.DakeOutput{}, &1)) do
        commands ++
          [
            %Docker.Command{
              instruction: "COPY",
              options: [%Docker.Command.Option{name: "from", value: docker.target}],
              arguments: "#{@dake_ouput_path} /"
            }
          ]
      else
        commands
      end

    {t_output(docker.target), commands}
  end

  @spec pipeline_targets([Target.Docker.t()]) :: [pipeline_target()]
  defp pipeline_targets(docker_targets) do
    Enum.flat_map(docker_targets, fn %Target.Docker{} = docker ->
      base_target_commands =
        docker.commands
        |> Enum.map(fn
          %Docker.Command{instruction: "FROM"} = command ->
            pipeline_from_as(command, docker.target)

          %Docker.Command{instruction: "COPY"} = command ->
            pipeline_copy_from(command)

          %Docker.Command{} = command ->
            command

          %Docker.Arg{} = arg ->
            argument = fmt_docker_arg_arguments(arg)

            %Docker.Command{instruction: "ARG", arguments: argument}

          %Docker.DakePush{} ->
            # TODO
            %Docker.Command{instruction: "#", arguments: "TODO DAKE_PUSH"}

          %Docker.DakeOutput{} = output ->
            arguments = "mkdir -p #{@dake_ouput_path} && mv #{output.dir} #{@dake_ouput_path}/"
            %Docker.Command{instruction: "RUN", arguments: arguments}
        end)

      target_output = pipeline_target_output(docker)

      [{docker.target, base_target_commands}, target_output]
    end)
  end

  @spec pipeline_add_default_target([pipeline_target()]) :: [pipeline_target()]
  defp pipeline_add_default_target(targets) do
    commands =
      targets
      |> Enum.reject(fn {target, _} -> String.starts_with?(target, "output.") end)
      |> Enum.map(fn {target, _commands} -> command_copy_done(target) end)

    output_commands =
      targets
      |> Enum.filter(fn {target, _} -> String.starts_with?(target, "output.") end)
      |> Enum.map(fn {output_target, _commands} ->
        %Docker.Command{
          instruction: "COPY",
          options: [%Docker.Command.Option{name: "from", value: output_target}],
          arguments: "/ ."
        }
      end)

    default_target = {
      "default",
      [%Docker.Command{instruction: "FROM", arguments: "scratch as default"} | commands]
    }

    default_output_target = {
      "output.default",
      [%Docker.Command{instruction: "FROM", arguments: "scratch as output.default"} | output_commands]
    }

    targets ++ [default_target, default_output_target]
  end

  @spec pipeline_add_targets_done([pipeline_target()]) :: [[pipeline_target()]]
  defp pipeline_add_targets_done(pipeline_targets) do
    Enum.map(pipeline_targets, fn {target, commands} ->
      commands = commands ++ [command_copy_done("base")]

      {target, commands}
    end)
  end

  @spec pipeline_from_as(Docker.Command.t(), String.t()) :: Docker.Command.t()
  defp pipeline_from_as(%Docker.Command{} = command, target) do
    from_target =
      case command.arguments do
        "+" <> from_target -> from_target
        from_target -> from_target
      end

    arguments = "#{from_target} AS #{target}"
    %Docker.Command{command | arguments: arguments}
  end

  @spec pipeline_copy_from(Docker.Command.t()) :: Docker.Command.t()
  defp pipeline_copy_from(%Docker.Command{instruction: "COPY", options: options} = command) do
    options =
      Enum.map(options || [], fn
        %Docker.Command.Option{name: "from", value: "+" <> target} = option ->
          %Docker.Command.Option{option | value: target}

        option ->
          option
      end)

    %Docker.Command{command | options: options}
  end

  @spec command_copy_done(from :: String.t()) :: Docker.Command.t()
  defp command_copy_done(from) do
    %Docker.Command{
      instruction: "COPY",
      options: [%Docker.Command.Option{name: "from", value: from}],
      arguments: "#{@dake_done_path} #{@dake_done_path}"
    }
  end

  @spec fmt_pipeline_args([Docker.Arg.t()]) :: String.t()
  defp fmt_pipeline_args(args) do
    Enum.map_join(args, "\n", &"#{fmt_docker_arg(&1)}")
  end

  @spec fmt_done_target :: String.t()
  defp fmt_done_target do
    """
    FROM busybox AS base
    RUN touch #{@dake_done_path}
    """
  end

  @spec fmt_pipeline_targets([pipeline_target()]) :: String.t()
  defp fmt_pipeline_targets(targets) do
    Enum.map_join(targets, "\n", fn {target, commands} ->
      commands = Enum.map_join(commands, "\n", &fmt_docker_command(&1))

      """
      # ---- #{target} ----

      #{commands}
      """
    end)
  end

  @spec fmt_docker_arg(Docker.Arg.t()) :: String.t()
  defp fmt_docker_arg(%Docker.Arg{} = arg) do
    "ARG #{fmt_docker_arg_arguments(arg)}"
  end

  @spec fmt_docker_arg_arguments(Docker.Arg.t()) :: String.t()
  defp fmt_docker_arg_arguments(%Docker.Arg{} = arg) do
    if arg.default_value do
      "#{arg.name}=#{arg.default_value}"
    else
      "#{arg.name}"
    end
  end

  @spec fmt_docker_command(Docker.Command.t()) :: String.t()
  defp fmt_docker_command(%Docker.Command{} = command) do
    options = Enum.map_join(command.options || [], " ", &"--#{&1.name}=#{&1.value}")
    "#{command.instruction} #{options} #{command.arguments}"
  end

  @spec t_output(target :: String.t()) :: String.t()
  defp t_output(target) do
    "output.#{target}"
  end
end
