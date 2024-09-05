# coveralls-ignore-start

defmodule Cake.Pipeline.Local do
  alias Cake.{Dir, Reporter}
  alias Cake.Parser.Target.Container.Arg
  alias Cake.Parser.Target.Local
  require Logger

  @behaviour Cake.Pipeline.Behaviour.Local

  @impl true
  def run(%Local{tgid: tgid, interpreter: interpreter, script: script, args: args}, run_env, pipeline_uuid) do
    into_reporter = Reporter.into(tgid, :log)

    Logger.info("target #{inspect(tgid)}", pipeline: pipeline_uuid)

    tmp_script_path = Path.join(Dir.tmp(), "#{pipeline_uuid}-local-script-#{tgid}")
    File.write!(tmp_script_path, script)

    cmd_args = String.split(interpreter) ++ [tmp_script_path]

    env =
      args
      |> Map.new(fn %Arg{} = arg -> {arg.name, arg.default_value} end)
      |> Map.merge(Map.new(run_env))

    case System.cmd(Dir.cmd_wrapper_path(), cmd_args, [stderr_to_stdout: true, env: env] ++ into_reporter) do
      {_, 0} -> :ok
      {_, _exit_status} -> raise Cake.Pipeline.Error, "Target #{tgid} failed"
    end
  end
end

# coveralls-ignore-stop
