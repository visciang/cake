# coveralls-ignore-start

defmodule Cake.Pipeline.Local do
  alias Cake.{Dir, Reporter}
  alias Cake.Parser.Target.Container.Env
  alias Cake.Parser.Target.Local
  require Logger

  @behaviour Cake.Pipeline.Behaviour.Local

  @impl true
  def run(%Local{tgid: tgid, interpreter: interpreter, script: script, env: env}, run_env, pipeline_uuid) do
    into_reporter = Reporter.into(tgid, :log)

    Logger.info("target #{inspect(tgid)}", pipeline: pipeline_uuid)

    tmp_script_path = Path.join(Dir.tmp(), "#{pipeline_uuid}-local-script-#{tgid}")
    File.write!(tmp_script_path, script)

    args = String.split(interpreter) ++ [tmp_script_path]

    env =
      env
      |> Map.new(fn %Env{} = e -> {e.name, e.default_value} end)
      |> Map.merge(Map.new(run_env))

    case System.cmd(Dir.cmd_wrapper_path(), args, [stderr_to_stdout: true, env: env] ++ into_reporter) do
      {_, 0} -> :ok
      {_, _exit_status} -> raise Cake.Pipeline.Error, "Target #{tgid} failed"
    end
  end
end

# coveralls-ignore-stop
