defmodule Cake.Reference do
  alias Cake.Parser.Directive
  alias Cake.{Dir, Reporter}

  use GenServer

  @name __MODULE__

  @type result :: {:ok, Path.t()} | {:error, reason :: String.t()}

  @spec start_link :: :ok
  def start_link do
    {:ok, _pid} = GenServer.start_link(__MODULE__, [], name: @name)
    :ok
  end

  @spec get_include(Directive.Include.t(), base_path :: Path.t()) :: result()
  def get_include(%Directive.Include{} = include, base_path) do
    GenServer.call(@name, {:get_include, include, base_path}, :infinity)
  end

  @impl GenServer
  def init([]) do
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:get_include, %Directive.Include{} = include, base_path}, _from, state) do
    res =
      case include.ref do
        "git+" <> git_url ->
          Reporter.job_notice("@include", "#{git_url}")
          git_ref("@include", git_url)

        include_dir ->
          Reporter.job_notice("@include", "#{include_dir}")
          include_local("@include", Path.join(base_path, include_dir))
      end
      |> case do
        {:ok, _} = ok -> ok
        {:error, reason} -> {:error, "@include #{include.ref} failed: #{reason}"}
      end

    {:reply, res, state}
  end

  @spec include_local(String.t(), Path.t()) :: result()
  defp include_local(_job_id, include_dir) do
    with {:dir?, true} <- {:dir?, File.dir?(include_dir)},
         {:execdir_subpath?, true} <- {:execdir_subpath?, subpath?(include_dir, Dir.execdir())} do
      if subpath?(include_dir, ".") do
        # include from a subdir of the current project workdir
        {:ok, include_dir}
      else
        # include from a parent dir of the current project workdir
        res_include_path = Path.join(Cake.Dir.include(), dir_slug(include_dir))

        File.rm_rf!(res_include_path)
        File.mkdir_p!(res_include_path)
        File.cp_r!(include_dir, res_include_path)

        {:ok, res_include_path}
      end
    else
      {:dir?, false} ->
        {:error, "directory not found"}

      {:execdir_subpath?, false} ->
        {:error, "'#{include_dir}' is not a sub-directory of the cake execution directory"}
    end
  end

  @spec git_ref(String.t(), Path.t()) :: result()
  defp git_ref(job_id, git_url) do
    with {:ok, git_repo, git_dir, git_ref} <- parse_git_url(git_url) do
      checkout_dir = Path.join(Cake.Dir.include(), dir_slug(git_repo <> "#" <> git_ref))
      checkout_cakefile_path = Path.join(checkout_dir, git_dir)
      cmd_opts = [stderr_to_stdout: true, cd: checkout_dir]

      if File.dir?(checkout_dir) do
        Reporter.job_notice(job_id, "using cached repository")

        # pull from remote (if on a branch)
        _ = System.cmd("git", ["pull", "--rebase"], cmd_opts)

        {:ok, checkout_cakefile_path}
      else
        File.mkdir_p!(checkout_dir)

        with {_tag, {_, 0}} <- {:clone, System.cmd("git", ["clone", git_repo, "."], cmd_opts)},
             {_tag, {_, 0}} <- {:checkout, System.cmd("git", ["checkout", git_ref], cmd_opts)} do
          {:ok, checkout_cakefile_path}
        else
          {action, {stderr, _exit_status}} ->
            File.rm_rf!(checkout_dir)
            {:error, "#{action} error: \n#{stderr} "}
        end
      end
    end
  end

  @spec parse_git_url(String.t()) ::
          {:ok, repo :: String.t(), dir :: String.t(), ref :: String.t()} | {:error, String.t()}
  defp parse_git_url(git_url) do
    with {:ref, [repo_url, ref]} <- {:ref, :string.split(git_url, "#", :trailing)},
         {:dir, [repo_url, dir]} <- {:dir, :string.split(repo_url, ".git", :trailing)} do
      {:ok, repo_url, dir, ref}
    else
      {:ref, _} ->
        {:error, "bad git repo format - expected <git_repo>#<REF> where `ref` can be a commit hash / tag / branch"}

      {:dir, _} ->
        {:error, "bad git repo format - expected git_repo.git[subdir]#<REF>"}
    end
  end

  defp subpath?(sub_path, base_path) do
    sub_path = sub_path |> Path.expand() |> Path.split()
    base_path = base_path |> Path.expand() |> Path.split()

    Enum.take(sub_path, length(base_path)) == base_path
  end

  @spec dir_slug(Path.t()) :: Path.t()
  defp dir_slug(dir) do
    dir
    |> String.replace("/", "_")
    |> String.replace(".", "-")
  end
end
