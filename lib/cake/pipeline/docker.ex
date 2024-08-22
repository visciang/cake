# coveralls-ignore-start

defmodule Cake.Pipeline.Docker do
  alias Cake.{Dir, Reporter, Type}
  require Logger

  @behaviour Cake.Pipeline.Behaviour.Container

  @impl true
  def fq_image(tgid, pipeline_uuid), do: "#{tgid}:#{pipeline_uuid}"

  @impl true
  def fq_output_container(tgid, pipeline_uuid), do: "output-#{tgid}-#{pipeline_uuid}"

  @impl true
  # credo:disable-for-next-line Credo.Check.Refactor.FunctionArity
  def build(tgid, tags, build_args, containerfile_path, no_cache, secrets, build_ctx, pipeline_uuid) do
    args =
      [
        ["--progress", "plain"],
        ["--file", containerfile_path],
        if(no_cache, do: ["--no-cache"], else: []),
        for(tag <- tags, do: ["--tag", tag]),
        for({name, value} <- build_args, do: ["--build-arg", "#{name}=#{value}"]),
        for(secret <- secrets, do: ["--secret", secret]),
        [build_ctx]
      ]
      |> List.flatten()

    args =
      if System.get_env("SSH_AUTH_SOCK", "") != "" do
        ["--ssh=default" | args]
      else
        args
      end

    args = [System.find_executable("docker"), "build" | args]
    into_reporter = Reporter.into(tgid, :log)

    Logger.info("target #{inspect(tgid)} #{inspect(args)}", pipeline: pipeline_uuid)

    case System.cmd(Dir.cmd_wrapper_path(), args, [stderr_to_stdout: true] ++ into_reporter) do
      {_, 0} -> :ok
      {_, _exit_status} -> raise Cake.Pipeline.Error, "Target #{tgid} failed"
    end
  end

  @impl true
  def shell(tgid, pipeline_uuid, devshell?) do
    docker_desktop_socket = "/run/host-services/ssh-auth.sock"

    ssh_sock =
      cond do
        :os.type() == {:unix, :darwin} ->
          Reporter.job_notice(tgid, ">>> detected Darwin OS - assuming docker desktop for SSH socket forwarding")
          docker_desktop_socket

        System.get_env("SSH_AUTH_SOCK") == nil ->
          Reporter.job_notice(tgid, ">>> SSH socket NOT forwarded")
          nil

        true ->
          ssh_auth_sock = System.get_env("SSH_AUTH_SOCK", "")
          Reporter.job_notice(tgid, ">>> forwarding SSH socket via #{inspect(ssh_auth_sock)}")
          ssh_auth_sock
      end

    run_ssh_args =
      case ssh_sock do
        nil -> []
        sock -> ["-e", "SSH_AUTH_SOCK=#{sock}", "-v", "#{sock}:#{sock}"]
      end

    run_devshell_args = if devshell?, do: ["--volume", ".:/devshell", "--workdir", "/devshell"], else: []

    run_cmd_args =
      ["run", "--rm", "-t", "-i", "--entrypoint", "sh"] ++
        run_ssh_args ++
        run_devshell_args ++
        [fq_image(tgid, pipeline_uuid)]

    port_opts = [:nouse_stdio, :exit_status, args: run_cmd_args]
    port = Port.open({:spawn_executable, System.find_executable("docker")}, port_opts)

    receive do
      {^port, {:exit_status, _}} -> :ok
    end

    :ok
  end

  @impl true
  def output(tgid, pipeline_uuid, outputs, output_dir) do
    container_image = fq_image(tgid, pipeline_uuid)
    tmp_container = fq_output_container(tgid, pipeline_uuid)

    container_create_cmd = ["container", "create", "--name", tmp_container, container_image]
    {_, 0} = System.cmd("docker", container_create_cmd, stderr_to_stdout: true)

    output_dir = Path.join(Dir.output(), output_dir)

    for output <- outputs do
      container_cp_cmd = ["container", "cp", "#{tmp_container}:#{output}", output_dir]
      into_reporter = Reporter.into(tgid, :log)

      case System.cmd("docker", container_cp_cmd, [stderr_to_stdout: true] ++ into_reporter) do
        {_, 0} -> :ok
        {_, _exit_status} -> raise Cake.Pipeline.Error, "Target #{tgid} output copy failed"
      end

      Reporter.job_output(tgid, "#{output} -> #{output_dir}")
    end

    :ok
  end

  @impl true
  def cleanup(pipeline_uuid) do
    rm_containers(pipeline_uuid)
    rm_images(pipeline_uuid)
  end

  @spec rm_images(Type.pipeline_uuid()) :: :ok
  defp rm_images(pipeline_uuid) do
    image_ls_args = ["image", "ls", fq_image("*", pipeline_uuid), "--format", "{{.Repository}}:{{.Tag}}", "--quiet"]
    {cmd_out, 0} = System.cmd("docker", image_ls_args)

    images = String.split(cmd_out, "\n", trim: true)

    if images != [] do
      _ = System.cmd("docker", ["image", "rm" | images], stderr_to_stdout: true)
    end

    :ok
  end

  @spec rm_containers(Type.pipeline_uuid()) :: :ok
  defp rm_containers(pipeline_uuid) do
    cmd = ["container", "ls", "--all", "--filter", "name=#{fq_output_container(".*", pipeline_uuid)}", "--quiet"]
    {cmd_out, 0} = System.cmd("docker", cmd)
    containers_ids = String.split(cmd_out, "\n", trim: true)

    if containers_ids != [] do
      _ = System.cmd("docker", ["container", "rm" | containers_ids], stderr_to_stdout: true)
    end

    :ok
  end
end

# coveralls-ignore-stop
