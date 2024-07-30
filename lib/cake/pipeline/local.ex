# coveralls-ignore-start

defmodule Cake.Pipeline.Local do
  alias Cake.{Dir, Reporter}
  alias Cake.Parser.Target.Container.Env
  alias Cake.Parser.Target.Local
  require Logger

  @behaviour Cake.Pipeline.Behaviour.Local

  @impl true
  def run(%Local{tgid: tgid, interpreter: interpreter, script: script, env: env}, run_env, pipeline_uuid) do
    into = Reporter.collector(tgid, :log)

    Logger.info("target #{inspect(tgid)}", pipeline: pipeline_uuid)

    args = String.split(interpreter) ++ [script]

    env = Map.new(env, fn %Env{} = e -> {e.name, e.default_value} end)
    env = Map.merge(env, run_env)

    case System.cmd(Dir.cmd_wrapper_path(), args, stderr_to_stdout: true, into: into, env: env) do
      {_, 0} -> :ok
      {_, _exit_status} -> raise Cake.Pipeline.Error, "Target #{tgid} failed"
    end
  end
end

# coveralls-ignore-stop
