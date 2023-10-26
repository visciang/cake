defmodule Dake.Pipeline.Docker do
  alias Dake.Cli.Run
  alias Dake.{Dir, Reporter, Type}

  require Logger

  @spec fq_image(Type.tgid(), Type.pipeline_uuid()) :: String.t()
  def fq_image(tgid, pipeline_uuid), do: "#{tgid}:#{pipeline_uuid}"

  @spec fq_output_container(Type.tgid(), Type.pipeline_uuid()) :: String.t()
  def fq_output_container(tgid, pipeline_uuid), do: "output-#{tgid}-#{pipeline_uuid}"

  @spec docker_build(Run.t(), Type.tgid(), [String.t()], Type.pipeline_uuid()) :: :ok
  def docker_build(%Run{} = run, tgid, args, pipeline_uuid) do
    docker = System.find_executable("docker")
    args = [docker, "buildx", "build" | args]
    into = Reporter.collector(run.ns, tgid)

    Logger.info("target #{inspect(tgid)} #{inspect(args)}", pipeline: pipeline_uuid)

    case System.cmd("/usr/bin/dake_cmd.sh", args, stderr_to_stdout: true, into: into) do
      {_, 0} -> :ok
      {_, _exit_status} -> raise Dake.Pipeline.Error, "Target #{tgid} failed"
    end
  end

  @spec docker_shell(Type.tgid(), Type.pipeline_uuid()) :: :ok
  def docker_shell(tgid, pipeline_uuid) do
    run_cmd_args = ["run", "--rm", "-t", "-i", "--entrypoint", "sh", fq_image(tgid, pipeline_uuid)]
    port_opts = [:nouse_stdio, :exit_status, args: run_cmd_args]
    port = Port.open({:spawn_executable, System.find_executable("docker")}, port_opts)

    receive do
      {^port, {:exit_status, _}} -> :ok
    end

    :ok
  end

  @spec docker_output(Run.t(), Type.tgid(), Type.pipeline_uuid(), [Path.t()]) :: :ok
  def docker_output(%Run{} = run, tgid, pipeline_uuid, outputs) do
    docker_image = fq_image(tgid, pipeline_uuid)
    tmp_container = fq_output_container(tgid, pipeline_uuid)

    container_create_cmd = ["container", "create", "--name", tmp_container, docker_image]
    {_, 0} = System.cmd("docker", container_create_cmd, stderr_to_stdout: true)

    Enum.each(outputs, fn output ->
      output_dir = Path.join(Dir.output(), run.output_dir)
      container_cp_cmd = ["container", "cp", "#{tmp_container}:#{output}", output_dir]
      into = Reporter.collector(run.ns, tgid)

      case System.cmd("docker", container_cp_cmd, stderr_to_stdout: true, into: into) do
        {_, 0} -> :ok
        {_, _exit_status} -> raise Dake.Pipeline.Error, "Target #{tgid} output copy failed"
      end

      Reporter.job_output(run.ns, tgid, "#{output} -> #{output_dir}")
    end)

    :ok
  end

  @spec docker_cleanup(Type.pipeline_uuid()) :: :ok
  def docker_cleanup(pipeline_uuid) do
    docker_rm_containers(pipeline_uuid)
    docker_rm_images(pipeline_uuid)
  end

  @spec docker_rm_images(Type.pipeline_uuid()) :: :ok
  defp docker_rm_images(pipeline_uuid) do
    {cmd_out, 0} = System.cmd("docker", ["image", "ls", "*:#{pipeline_uuid}", "--format", "{{.Repository}}", "--quiet"])
    repositories = String.split(cmd_out, "\n", trim: true)

    if repositories != [] do
      images_ids = Enum.map(repositories, &fq_image(&1, pipeline_uuid))
      _ = System.cmd("docker", ["image", "rm" | images_ids], stderr_to_stdout: true)
    end

    :ok
  end

  @spec docker_rm_containers(Type.pipeline_uuid()) :: :ok
  defp docker_rm_containers(pipeline_uuid) do
    cmd = ["container", "ls", "--all", "--filter", "name=#{fq_output_container(".*", pipeline_uuid)}", "--quiet"]
    {cmd_out, 0} = System.cmd("docker", cmd)
    containers_ids = String.split(cmd_out, "\n", trim: true)

    if containers_ids != [] do
      _ = System.cmd("docker", ["container", "rm" | containers_ids], stderr_to_stdout: true)
    end

    :ok
  end
end