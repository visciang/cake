defmodule Cake.Reference do
  alias Cake.Parser.Directive
  alias Cake.Reporter

  use GenServer

  @name __MODULE__

  @type result :: {:ok, Path.t()} | {:error, reason :: String.t()}

  @spec start_link :: :ok
  def start_link do
    {:ok, _pid} = GenServer.start_link(__MODULE__, [], name: @name)
    :ok
  end

  @spec get_include(Directive.Include.t()) :: result()
  def get_include(%Directive.Include{} = include) do
    GenServer.call(@name, {:get_include, include}, :infinity)
  end

  @impl GenServer
  def init([]) do
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:get_include, %Directive.Include{} = include}, _from, state) do
    res =
      case include.ref do
        "git+" <> git_url ->
          Reporter.job_notice("@include", "#{git_url}")
          git_ref("@include", git_url)

        include_dir ->
          path = Path.join(include_dir, "Cakefile")

          {:ok, path}
      end
      |> case do
        {:ok, _} = ok -> ok
        {:error, reason} -> {:error, "@include #{include.ref} failed: #{reason}"}
      end

    {:reply, res, state}
  end

  @spec git_ref(String.t(), Path.t()) :: result()
  defp git_ref(job_id, git_url) do
    with {:ok, git_repo, git_dir, git_ref} <- parse_git_url(git_url) do
      checkout_dir = Path.join([Cake.Dir.git_ref(), git_repo <> "#" <> git_ref])
      checkout_cakefile_path = Path.join([checkout_dir, git_dir, "Cakefile"])
      cmd_opts = [stderr_to_stdout: true, cd: checkout_dir]

      if File.dir?(checkout_dir) do
        Reporter.job_notice(job_id, "using cached repository")

        # pull from remote (if on a branch)
        _ = System.cmd("git", ["pull"], cmd_opts)

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
end
