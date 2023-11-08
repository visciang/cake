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
    podman = System.find_executable("podman")
    args = if System.get_env("SSH_AUTH_SOCK"), do: ["--ssh=default" | args], else: args
    args = [podman, "build" | args]
    into = Reporter.collector(run.ns, tgid, :log)

    Logger.info("target #{inspect(tgid)} #{inspect(args)}", pipeline: pipeline_uuid)

    case System.cmd("/usr/bin/dake_cmd.sh", args, stderr_to_stdout: true, into: into) do
      {_, 0} -> :ok
      {_, _exit_status} -> raise Dake.Pipeline.Error, "Target #{tgid} failed"
    end
  end

  @spec docker_shell(Type.tgid(), Type.pipeline_uuid()) :: :ok
  def docker_shell(tgid, pipeline_uuid) do
    # TODO: rotto con podman, il problema sembra essere legato ad erlang / Port.
    #       da shell dentro il container di dake posso fare un "podman run --rm -ti ..."

    ssh_auth_sock = System.fetch_env!("SSH_AUTH_SOCK")
    run_ssh_args = ["-e", "SSH_AUTH_SOCK=#{ssh_auth_sock}", "-v", "#{ssh_auth_sock}:#{ssh_auth_sock}"]

    run_cmd_args = ["run", "--rm", "-t", "-i", "--entrypoint", "sh"] ++ run_ssh_args ++ [fq_image(tgid, pipeline_uuid)]

    port_opts = [:nouse_stdio, :exit_status, args: run_cmd_args]
    port = Port.open({:spawn_executable, System.find_executable("podman")}, port_opts)

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
    {_, 0} = System.cmd("podman", container_create_cmd, stderr_to_stdout: true)

    Enum.each(outputs, fn output ->
      output_dir = Path.join(Dir.output(), run.output_dir)
      container_cp_cmd = ["container", "cp", "#{tmp_container}:#{output}", output_dir]
      into = Reporter.collector(run.ns, tgid, :log)

      case System.cmd("podman", container_cp_cmd, stderr_to_stdout: true, into: into) do
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
    image_ls_args = ["image", "ls", fq_image("*", pipeline_uuid), "--format", "{{.ID}}", "--quiet"]
    {cmd_out, 0} = System.cmd("podman", image_ls_args)

    images = String.split(cmd_out, "\n", trim: true) |> Enum.uniq()

    Enum.each(images, fn image ->
      _ = System.cmd("podman", ["image", "untag", image], stderr_to_stdout: true)
    end)

    :ok
  end

  @spec docker_rm_containers(Type.pipeline_uuid()) :: :ok
  defp docker_rm_containers(pipeline_uuid) do
    cmd = ["container", "ls", "--all", "--filter", "name=#{fq_output_container(".*", pipeline_uuid)}", "--quiet"]
    {cmd_out, 0} = System.cmd("podman", cmd)
    containers_ids = String.split(cmd_out, "\n", trim: true)

    if containers_ids != [] do
      _ = System.cmd("podman", ["container", "rm" | containers_ids], stderr_to_stdout: true)
    end

    :ok
  end
end
