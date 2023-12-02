defmodule Cake.Pipeline.Compose do
  alias Cake.Cli.Run
  alias Cake.Parser.Directive
  alias Cake.{Reporter, Type}

  @spec run(Run.t(), Directive.ComposeRun.t(), Type.pipeline_uuid()) :: :ok
  def run(%Run{} = run, %Directive.ComposeRun{} = cr, pipeline_uuid) do
    compose(run, ["--file", cr.file, "run", "--rm" | cr.args], pipeline_uuid)
  end

  @spec down(Run.t(), Directive.ComposeRun.t(), Type.pipeline_uuid()) :: :ok
  def down(%Run{} = run, %Directive.ComposeRun{} = cr, pipeline_uuid) do
    compose(run, ["--file", cr.file, "down", "--volumes"], pipeline_uuid)
  end

  @spec compose(Run.t(), args :: [String.t()], Type.pipeline_uuid()) :: :ok
  defp compose(%Run{} = run, args, pipeline_uuid) do
    args = [System.find_executable("docker"), "compose" | args]
    into = Reporter.collector(run.ns, run.tgid, :log)
    env = [{"CAKE_PIPELINE_UUID", pipeline_uuid}]

    Reporter.job_notice(run.ns, run.tgid, Enum.join(args, " "))

    case System.cmd("/usr/bin/cake_cmd.sh", args, stderr_to_stdout: true, into: into, env: env) do
      {_, 0} -> :ok
      {_, _exit_status} -> raise Cake.Pipeline.Error, "Compose run #{run.tgid} failed"
    end
  end
end
