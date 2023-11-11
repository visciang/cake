defmodule Dake.Reference do
  alias Dake.Parser.{Dakefile, Directive}
  alias Dake.{Dir, Reporter}

  require Logger

  use GenServer

  @name __MODULE__

  @type result :: {:ok, Path.t()} | {:error, reason :: String.t()}

  @spec start_link :: :ok
  def start_link do
    {:ok, _pid} = GenServer.start_link(__MODULE__, [], name: @name)
    :ok
  end

  @spec get_include(Dakefile.t(), Directive.Include.t()) :: result()
  def get_include(%Dakefile{} = dakefile, %Directive.Include{} = include) do
    GenServer.call(@name, {:get_include, dakefile, include}, :infinity)
  end

  @spec get_import(Directive.Import.t()) :: result()
  def get_import(%Directive.Import{} = import_) do
    GenServer.call(@name, {:get_import, import_}, :infinity)
  end

  @impl true
  def init([]) do
    {:ok, %{}}
  end

  @impl true
  def handle_call(
        {:get_include, %Dakefile{} = dakefile, %Directive.Include{} = include},
        _from,
        state
      ) do
    res =
      case include.ref do
        "git+" <> git_url ->
          Reporter.job_notice([], "git", "@include #{git_url}")
          git_ref(git_url)

        local_path ->
          # include path normalizated to be relative to the project root directory
          path = Path.join([Path.dirname(dakefile.path), local_path, "Dakefile"])

          case Path.safe_relative(path) do
            {:ok, path} ->
              copy_include_ctx(dakefile, path)
              {:ok, path}

            :error ->
              {:error, "#{local_path} path out of the project root directory"}
          end
      end
      |> case do
        {:ok, _} = ok -> ok
        {:error, reason} -> {:error, "@include #{include.ref} failed: #{reason}"}
      end

    {:reply, res, state}
  end

  @impl true
  def handle_call({:get_import, %Directive.Import{} = import_}, _from, state) do
    res =
      case import_.ref do
        "git+" <> git_url ->
          Reporter.job_notice([], "git", "@import #{git_url}")
          git_ref(git_url)

        local_path ->
          {:ok, Path.join(local_path, "Dakefile")}
      end
      |> case do
        {:ok, _} = ok -> ok
        {:error, reason} -> {:error, "@import #{import_.ref} failed: #{reason}"}
      end

    {:reply, res, state}
  end

  @spec git_ref(String.t()) :: result()
  defp git_ref(git_url) do
    checkout_dir = Path.join(Dake.Dir.git_ref(), git_url)

    if File.dir?(checkout_dir) do
      Reporter.job_notice([], "git", "using cached repository")
      {:ok, Path.join(checkout_dir, "Dakefile")}
    else
      File.mkdir_p!(checkout_dir)

      into = Reporter.collector([], "git", :log)
      cmd_opts = [stderr_to_stdout: true, cd: checkout_dir, into: into]

      with {:git_ref, {:ok, git_repo, git_ref}} <- {:git_ref, parse_git_url(git_url)},
           {:clone, {_, 0}} <- {:clone, System.cmd("git", ["clone", git_repo, "."], cmd_opts)},
           {:checkout, {_, 0}} <- {:checkout, System.cmd("git", ["checkout", git_ref], cmd_opts)} do
        {:ok, Path.join(checkout_dir, "Dakefile")}
      else
        {action, _exit_status} ->
          File.rm_rf!(checkout_dir)
          {:error, "#{action} error"}
      end
    end
  end

  @spec parse_git_url(String.t()) ::
          {:ok, repo :: String.t(), ref :: String.t()} | {:error, String.t()}
  defp parse_git_url(git_url) do
    case :string.split(git_url, "#", :trailing) do
      [repo_url, ref] ->
        {:ok, repo_url, ref}

      _ ->
        {:error, "bad git repo format - expected <git_repo>#<REF> where `ref` can be a commit hash / tag / branch"}
    end
  end

  @spec copy_include_ctx(Dakefile.t(), Path.t()) :: :ok
  defp copy_include_ctx(%Dakefile{} = dakefile, included_dakefile_path) do
    include_ctx_dir = Path.join(Path.dirname(included_dakefile_path), "ctx")

    dest = Dir.local_include_ctx_dir(dakefile.path, included_dakefile_path)

    if File.exists?(include_ctx_dir) and not File.exists?(dest) do
      Logger.info("from #{inspect(included_dakefile_path)}")

      File.rm_rf!(dest)
      File.mkdir_p!(dest)
      File.cp_r!(include_ctx_dir, dest)
    end

    :ok
  end
end
