defmodule Cake.Pipeline.Container do
  alias Cake.Cli.Run
  alias Cake.{Dir, Reporter, Type}

  require Logger

  @spec fq_image(Type.tgid(), Type.pipeline_uuid()) :: String.t()
  def fq_image(tgid, pipeline_uuid), do: "#{tgid}:#{pipeline_uuid}"

  @spec fq_output_container(Type.tgid(), Type.pipeline_uuid()) :: String.t()
  def fq_output_container(tgid, pipeline_uuid), do: "output-#{tgid}-#{pipeline_uuid}"

  @spec container_build(Run.t(), Type.tgid(), [String.t()], Type.pipeline_uuid()) :: :ok
  def container_build(%Run{} = run, tgid, args, pipeline_uuid) do
    container = System.find_executable("docker")
    args = if System.get_env("SSH_AUTH_SOCK"), do: ["--ssh=default" | args], else: args
    args = [container, "build" | args]
    into = Reporter.collector(run.ns, tgid, :log)

    Logger.info("target #{inspect(tgid)} #{inspect(args)}", pipeline: pipeline_uuid)

    case System.cmd("/usr/bin/cake_cmd.sh", args, stderr_to_stdout: true, into: into) do
      {_, 0} -> :ok
      {_, _exit_status} -> raise Cake.Pipeline.Error, "Target #{tgid} failed"
    end
  end

  @spec container_shell(Type.tgid(), Type.pipeline_uuid()) :: :ok
  def container_shell(tgid, pipeline_uuid) do
    ssh_auth_sock = System.fetch_env!("SSH_AUTH_SOCK")
    run_ssh_args = ["-e", "SSH_AUTH_SOCK=#{ssh_auth_sock}", "-v", "#{ssh_auth_sock}:#{ssh_auth_sock}"]
    run_cmd_args = ["run", "--rm", "-t", "-i", "--entrypoint", "sh"] ++ run_ssh_args ++ [fq_image(tgid, pipeline_uuid)]
    port_opts = [:nouse_stdio, :exit_status, args: run_cmd_args]
    port = Port.open({:spawn_executable, System.find_executable("docker")}, port_opts)

    receive do
      {^port, {:exit_status, _}} -> :ok
    end

    :ok
  end

  @spec container_output(Run.t(), Type.tgid(), Type.pipeline_uuid(), [Path.t()]) :: :ok
  def container_output(%Run{} = run, tgid, pipeline_uuid, outputs) do
    container_image = fq_image(tgid, pipeline_uuid)
    tmp_container = fq_output_container(tgid, pipeline_uuid)

    container_create_cmd = ["container", "create", "--name", tmp_container, container_image]
    {_, 0} = System.cmd("docker", container_create_cmd, stderr_to_stdout: true)

    Enum.each(outputs, fn output ->
      output_dir = Path.join(Dir.output(), run.output_dir)
      container_cp_cmd = ["container", "cp", "#{tmp_container}:#{output}", output_dir]
      into = Reporter.collector(run.ns, tgid, :log)

      case System.cmd("docker", container_cp_cmd, stderr_to_stdout: true, into: into) do
        {_, 0} -> :ok
        {_, _exit_status} -> raise Cake.Pipeline.Error, "Target #{tgid} output copy failed"
      end

      Reporter.job_output(run.ns, tgid, "#{output} -> #{output_dir}")
    end)

    :ok
  end

  @spec container_cleanup(Type.pipeline_uuid()) :: :ok
  def container_cleanup(pipeline_uuid) do
    container_rm_containers(pipeline_uuid)
    container_rm_images(pipeline_uuid)
  end

  @spec container_rm_images(Type.pipeline_uuid()) :: :ok
  defp container_rm_images(pipeline_uuid) do
    image_ls_args = ["image", "ls", fq_image("*", pipeline_uuid), "--format", "{{.Repository}}:{{.Tag}}", "--quiet"]
    {cmd_out, 0} = System.cmd("docker", image_ls_args)

    images = String.split(cmd_out, "\n", trim: true)

    if images != [] do
      _ = System.cmd("docker", ["image", "rm" | images], stderr_to_stdout: true)
    end

    :ok
  end

  @spec container_rm_containers(Type.pipeline_uuid()) :: :ok
  defp container_rm_containers(pipeline_uuid) do
    cmd = ["container", "ls", "--all", "--filter", "name=#{fq_output_container(".*", pipeline_uuid)}", "--quiet"]
    {cmd_out, 0} = System.cmd("docker", cmd)
    containers_ids = String.split(cmd_out, "\n", trim: true)

    if containers_ids != [] do
      _ = System.cmd("docker", ["container", "rm" | containers_ids], stderr_to_stdout: true)
    end

    :ok
  end
end
