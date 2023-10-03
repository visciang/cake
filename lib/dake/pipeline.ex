defmodule Dake.Pipeline do
  @moduledoc """
  Pipeline builder.
  """

  alias Dake.Parser.Dakefile
  alias Dake.Parser.Docker
  alias Dake.Parser.Target
  alias Dake.Type

  @dake_done_path "/.dake_done"
  @dake_ouput_path "/.dake_output"

  @typep pipeline_target :: {Type.tgid(), [Docker.From.t() | Docker.Arg.t() | Docker.Command.t()]}

  @spec build(Dakefile.t(), push :: boolean()) :: Path.t()
  def build(%Dakefile{} = dakefile, push) do
    pipeline_args = pipeline_args(dakefile.args)

    pipeline_docker_targets =
      dakefile.targets
      |> Enum.filter(&match?(%Target.Docker{}, &1))
      |> pipeline_targets(push)
      |> pipeline_add_default_target()
      |> pipeline_add_targets_done()

    pipeline_alias_targets =
      dakefile.targets
      |> Enum.filter(&match?(%Target.Alias{}, &1))
      |> pipeline_aliases()
      |> pipeline_add_targets_done()

    dockerfile_path = "Dockerfile"

    dockerfile = """
    # ==== pipeline ARGs ====

    #{fmt_pipeline_args(pipeline_args)}

    # ==== pipeline targets ====

    #{fmt_done_target()}
    #{fmt_pipeline_targets(pipeline_docker_targets)}

    # ==== pipeline aliases ====

    #{fmt_pipeline_targets(pipeline_alias_targets)}
    """

    File.write!(dockerfile_path, dockerfile)

    dockerfile_path
  end

  @spec pipeline_args([Docker.Arg.t()]) :: [Docker.Arg.t()]
  defp pipeline_args(args), do: args

  @spec pipeline_aliases([Target.Alias.t()]) :: [pipeline_target()]
  defp pipeline_aliases(aliases) do
    Enum.map(aliases, fn %Target.Alias{} = alias_ ->
      from = %Docker.From{image: "scratch", as: alias_.tgid}
      commands = Enum.map(alias_.tgids, fn tgid -> command_copy_done(tgid) end)

      {alias_.tgid, [from | commands]}
    end)
  end

  @spec pipeline_targets([Target.Docker.t()], push :: boolean()) :: [pipeline_target()]
  defp pipeline_targets(docker_targets, push) do
    push_targets = push_targets_set(docker_targets)

    Enum.flat_map(docker_targets, fn %Target.Docker{} = docker ->
      docker =
        if push and MapSet.member?(push_targets, docker) do
          force_push_arg = %Docker.Arg{name: String.upcase(docker.tgid)}
          [from | rest_commands] = docker.commands
          commands = [from, force_push_arg | rest_commands]
          %Target.Docker{docker | commands: commands}
        else
          docker
        end

      if not push and MapSet.member?(push_targets, docker) do
        []
      else
        target = pipeline_target(docker)
        target_output = pipeline_target_output(docker)

        [target, target_output]
      end
    end)
  end

  @spec pipeline_target(Target.Docker.t()) :: pipeline_target()
  defp pipeline_target(%Target.Docker{} = docker) do
    commands =
      docker.commands
      |> Enum.map(fn
        %Docker.From{} = from ->
          image = String.trim_leading(from.image, "+")
          %Docker.From{image: image, as: docker.tgid}

        %Docker.Command{instruction: "COPY"} = command ->
          pipeline_copy_from(command)

        %Docker.Command{} = command ->
          command

        %Docker.Arg{} = arg ->
          arg
      end)

    output_commands =
      docker.directives
      |> Enum.filter(&match?(%Docker.DakeOutput{}, &1))
      |> Enum.map(fn %Docker.DakeOutput{} = output ->
        arguments = "mkdir -p #{@dake_ouput_path} && cp -r #{output.dir} #{@dake_ouput_path}/"
        %Docker.Command{instruction: "RUN", arguments: arguments}
      end)

    {docker.tgid, commands ++ output_commands}
  end

  @spec pipeline_target_output(Target.Docker.t()) :: pipeline_target()
  defp pipeline_target_output(%Target.Docker{} = docker) do
    commands = [
      %Docker.From{image: "scratch", as: t_output(docker.tgid)},
      command_copy_done(docker.tgid)
    ]

    commands =
      if Enum.any?(docker.directives, &match?(%Docker.DakeOutput{}, &1)) do
        copy_output_command = %Docker.Command{
          instruction: "COPY",
          options: [%Docker.Command.Option{name: "from", value: docker.tgid}],
          arguments: "#{@dake_ouput_path} /"
        }

        commands ++ [copy_output_command]
      else
        commands
      end

    {t_output(docker.tgid), commands}
  end

  @spec pipeline_add_default_target([pipeline_target()]) :: [pipeline_target()]
  defp pipeline_add_default_target(targets) do
    commands =
      targets
      |> Enum.reject(fn {tgid, _} -> String.starts_with?(tgid, "output.") end)
      |> Enum.map(fn {tgid, _commands} -> command_copy_done(tgid) end)

    output_commands =
      targets
      |> Enum.filter(fn {tgid, _} -> String.starts_with?(tgid, "output.") end)
      |> Enum.map(fn {output_tgid, _commands} ->
        %Docker.Command{
          instruction: "COPY",
          options: [%Docker.Command.Option{name: "from", value: output_tgid}],
          arguments: "/ ."
        }
      end)

    default_target = {
      "default",
      [%Docker.From{image: "scratch", as: "default"} | commands]
    }

    default_output_target = {
      "output.default",
      [%Docker.From{image: "scratch", as: "output.default"} | output_commands]
    }

    targets ++ [default_target, default_output_target]
  end

  @spec pipeline_add_targets_done([pipeline_target()]) :: [[pipeline_target()]]
  defp pipeline_add_targets_done(pipeline_targets) do
    Enum.map(pipeline_targets, fn {tgid, commands} ->
      commands = commands ++ [command_copy_done("base")]

      {tgid, commands}
    end)
  end

  @spec pipeline_copy_from(Docker.Command.t()) :: Docker.Command.t()
  defp pipeline_copy_from(%Docker.Command{instruction: "COPY", options: options} = command) do
    options =
      Enum.map(options, fn
        %Docker.Command.Option{name: "from", value: "+" <> tgid} = option ->
          %Docker.Command.Option{option | value: tgid}

        option ->
          option
      end)

    %Docker.Command{command | options: options}
  end

  @spec push_targets_set([Target.Docker.t()]) :: MapSet.t(Target.Docker.t())
  defp push_targets_set(docker_targets) do
    docker_targets
    |> Enum.filter(fn
      %Target.Docker{} = docker ->
        Enum.any?(docker.directives, &match?(%Docker.DakePush{}, &1))

      _ ->
        false
    end)
    |> MapSet.new()
  end

  @spec command_copy_done(from :: Type.tgid()) :: Docker.Command.t()
  defp command_copy_done(from) do
    %Docker.Command{
      instruction: "COPY",
      options: [%Docker.Command.Option{name: "from", value: from}],
      arguments: "#{@dake_done_path} #{@dake_done_path}"
    }
  end

  @spec fmt_pipeline_args([Docker.Arg.t()]) :: String.t()
  defp fmt_pipeline_args(args) do
    Enum.map_join(args, "\n", &"#{fmt(&1)}")
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
      commands = Enum.map_join(commands, "\n", &fmt(&1))

      """
      # ---- #{target} ----

      #{commands}
      """
    end)
  end

  @spec fmt(Docker.From.t()) :: String.t()
  defp fmt(%Docker.From{} = from) do
    if from.as do
      "FROM #{from.image} AS #{from.as}"
    else
      "FROM #{from.image}"
    end
  end

  @spec fmt(Docker.Arg.t()) :: String.t()
  defp fmt(%Docker.Arg{} = arg) do
    arg =
      if arg.default_value do
        "#{arg.name}=#{arg.default_value}"
      else
        arg.name
      end

    "ARG #{arg}"
  end

  @spec fmt(Docker.Command.t()) :: String.t()
  defp fmt(%Docker.Command{} = command) do
    options = Enum.map_join(command.options, " ", &"--#{&1.name}=#{&1.value}")
    "#{command.instruction} #{options} #{command.arguments}"
  end

  @spec t_output(Type.tgid()) :: Type.tgid()
  defp t_output(tgid) do
    "output.#{tgid}"
  end
end
