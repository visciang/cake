# coveralls-ignore-start

defmodule Cake.Reporter.State do
  alias Cake.Reporter
  alias Cake.Reporter.Status

  @enforce_keys [
    :reporter,
    :logs_to_file,
    :logs_dir,
    :job_to_log_file,
    :start_time,
    :track,
    :reporter_state
  ]
  defstruct @enforce_keys

  @type job :: String.t()
  @type job_status :: %{job() => Status.t() | {:running, start_time :: integer()}}

  @type t :: %__MODULE__{
          reporter: Reporter.behaviour(),
          logs_to_file: boolean(),
          logs_dir: Path.t(),
          job_to_log_file: %{job() => File.io_device()},
          start_time: integer(),
          track: job_status(),
          reporter_state: term()
        }
end

defmodule Cake.Reporter do
  use GenServer

  alias Cake.{Dir, Reporter, Type}
  alias Cake.Reporter.{Collector, Duration, Icon, State, Status}

  require Cake.Reporter.Status

  @typep ansidata :: IO.ANSI.ansidata()

  # ---- behaviour

  @type reporter_state :: term()
  @type behaviour :: module()
  @callback init :: reporter_state()
  @callback job_start(State.job(), reporter_state()) :: {nil | ansidata(), reporter_state()}
  @callback job_end(State.job(), Status.t(), duration :: String.t(), reporter_state()) ::
              {nil | ansidata(), reporter_state()}
  @callback job_log(State.job(), msg :: String.t(), reporter_state()) :: {nil | ansidata(), reporter_state()}
  @callback job_output(State.job(), output :: Path.t(), reporter_state()) :: {nil | ansidata(), reporter_state()}
  @callback job_notice(State.job(), String.t(), reporter_state()) :: {nil | ansidata(), reporter_state()}
  @callback job_shell_start(State.job(), reporter_state()) :: {nil | ansidata(), reporter_state()}
  @callback job_shell_end(State.job(), reporter_state()) :: {nil | ansidata(), reporter_state()}
  @callback info({reporter :: module(), msg :: term()}, reporter_state()) :: reporter_state()

  # ----

  @name __MODULE__

  @spec start_link(progress :: Type.progress(), logs_to_file :: boolean()) :: :ok
  def start_link(progress, logs_to_file) do
    {:ok, _pid} = GenServer.start_link(__MODULE__, [progress, logs_to_file], name: @name)
    :ok
  end

  @spec stop(Cake.Cmd.result()) :: :ok
  def stop(workflow_status) do
    GenServer.call(@name, {:stop, workflow_status}, :infinity)
  end

  @spec job_start(String.t()) :: :ok
  def job_start(job_id) do
    GenServer.cast(@name, {:job_start, job_id})
  end

  @spec job_end(String.t(), Status.t()) :: :ok
  def job_end(job_id, status) do
    GenServer.cast(@name, {:job_end, job_id, status})
  end

  @spec job_notice(String.t(), String.t()) :: :ok
  def job_notice(job_id, message) do
    GenServer.cast(@name, {:job_notice, job_id, message})
  end

  @spec job_log(String.t(), String.t()) :: :ok
  def job_log(job_id, message) do
    GenServer.cast(@name, {:job_log, job_id, message})
  end

  @spec job_output(String.t(), Path.t()) :: :ok
  def job_output(job_id, output_path) do
    GenServer.cast(@name, {:job_output, job_id, output_path})
  end

  @spec job_shell_start(String.t()) :: :ok
  def job_shell_start(job_id) do
    GenServer.call(@name, {:job_shell_start, job_id})
    :ok
  end

  @spec job_shell_end(String.t()) :: :ok
  def job_shell_end(job_id) do
    GenServer.call(@name, {:job_shell_end, job_id})
    :ok
  end

  @spec into(String.t(), Collector.report_type()) :: system_cmd_opts :: [into: Collectable.t(), lines: pos_integer()]
  def into(job_id, type) do
    [into: %Collector{job_id: job_id, type: type}, lines: 1024]
  end

  @impl GenServer
  def init([progress, logs_to_file]) do
    reporter =
      case progress do
        :plain -> Reporter.Plain
        :interactive -> Reporter.Interactive
      end

    state =
      %State{
        reporter: reporter,
        logs_to_file: logs_to_file,
        logs_dir: Path.join(Dir.log(), DateTime.utc_now() |> DateTime.to_iso8601()),
        job_to_log_file: %{},
        start_time: Duration.time(),
        track: %{},
        reporter_state: reporter.init()
      }

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:job_start, job_id}, %State{} = state) do
    state = set_log_file(job_id, state)
    log_file = get_log_file(job_id, state)

    {ansidata, reporter_state} = state.reporter.job_start(job_id, state.reporter_state)
    log_to_file(state.logs_to_file, log_file, ansidata)

    state = put_in(state.track[job_id], {:running, Duration.time()})
    state = put_in(state.reporter_state, reporter_state)

    {:noreply, state}
  end

  def handle_cast({:job_end, job_id, status}, %State{} = state) do
    log_file = get_log_file(job_id, state)

    duration = job_duration(job_id, state)
    {ansidata, reporter_state} = state.reporter.job_end(job_id, status, duration, state.reporter_state)
    log_to_file(state.logs_to_file, log_file, ansidata)

    state = put_in(state.track[job_id], status)
    state = put_in(state.reporter_state, reporter_state)

    {:noreply, state}
  end

  def handle_cast({:job_log, job_id, line}, %State{} = state) do
    log_file = get_log_file(job_id, state)

    {ansidata, reporter_state} = state.reporter.job_log(job_id, line, state.reporter_state)
    log_to_file(state.logs_to_file, log_file, ansidata)

    state = put_in(state.reporter_state, reporter_state)

    {:noreply, state}
  end

  def handle_cast({:job_notice, job_id, line}, %State{} = state) do
    {_ansidata, reporter_state} = state.reporter.job_notice(job_id, line, state.reporter_state)

    state = put_in(state.reporter_state, reporter_state)

    {:noreply, state}
  end

  def handle_cast({:job_output, job_id, output_path}, %State{} = state) do
    log_file = get_log_file(job_id, state)

    {ansidata, reporter_state} = state.reporter.job_output(job_id, output_path, state.reporter_state)
    log_to_file(state.logs_to_file, log_file, ansidata)

    state = put_in(state.reporter_state, reporter_state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:job_shell_start, job_id}, _from, %State{} = state) do
    log_file = get_log_file(job_id, state)

    {ansidata, reporter_state} = state.reporter.job_shell_start(job_id, state.reporter_state)
    log_to_file(state.logs_to_file, log_file, ansidata)

    state = put_in(state.reporter_state, reporter_state)

    {:reply, :ok, state}
  end

  def handle_call({:job_shell_end, job_id}, _from, %State{} = state) do
    log_file = get_log_file(job_id, state)

    {ansidata, reporter_state} = state.reporter.job_shell_end(job_id, state.reporter_state)
    log_to_file(state.logs_to_file, log_file, ansidata)

    state = put_in(state.reporter_state, reporter_state)

    {:reply, :ok, state}
  end

  def handle_call({:stop, workflow_status}, _from, %State{} = state) do
    if state.logs_to_file do
      log_stdout_puts("\nLogs directory: #{state.logs_dir}")

      for {_job_id, file} <- state.job_to_log_file do
        File.close(file)
      end
    end

    unless match?({:ignore, _}, workflow_status) do
      duration = Duration.delta_time_string(Duration.time() - state.start_time)
      end_message = end_message(workflow_status, state.track)

      log_stdout_puts(["\n", end_message, "\n"])
      log_stdout_puts("Elapsed #{duration}\n")
    end

    {:stop, :normal, :ok, state}
  end

  @impl GenServer
  def handle_info({reporter, _} = info, %State{reporter: reporter} = state) do
    reporter_state = reporter.info(info, state.reporter_state)
    state = put_in(state.reporter_state, reporter_state)

    {:noreply, state}
  end

  @spec end_message(Cake.Cmd.result(), State.job_status()) :: nil | ansidata()
  defp end_message(workflow_status, jobs_status) do
    case workflow_status do
      :ok ->
        [:green, "Run completed: ", :reset, status_count_message(jobs_status)]

      {:error, _} ->
        failed =
          for {job_id, status} <- jobs_status, match?(Status.error(_, _), status) or match?(Status.timeout(), status) do
            "- #{job_id}"
          end

        failed = Enum.join(failed, "\n")

        [:red, "Run failed: ", :reset, status_count_message(jobs_status), "\n", :red, failed, :reset]

      :timeout ->
        [:red, "Run timeout: ", :reset, status_count_message(jobs_status)]
    end
  end

  @spec status_count_message(State.job_status()) :: ansidata()
  defp status_count_message(jobs_status) do
    freq_by_status =
      jobs_status
      |> Map.values()
      |> Enum.frequencies_by(fn
        Status.ok() -> :ok
        Status.error(_, _) -> :error
        Status.timeout() -> :timeout
        {:running, _} -> :running
      end)

    freq_by_status = Map.merge(%{ok: 0, error: 0, timeout: 0}, freq_by_status)

    res =
      for status <- [:ok, :error, :timeout] do
        count = Map.get(freq_by_status, status, 0)
        [apply(Icon, status, []), " ", to_string(count)]
      end

    Enum.intersperse(res, ", ")
  end

  @spec job_duration(State.job(), State.t()) :: String.t()
  defp job_duration(job_id, %State{} = state) do
    end_time = Duration.time()

    start_time =
      case state.track[job_id] do
        {:running, start_time} -> start_time
        _ -> end_time
      end

    Duration.delta_time_string(end_time - start_time)
  end

  @spec log_to_file(emit? :: boolean(), File.io_device(), message :: nil | ansidata()) :: :ok
  defp log_to_file(false, _log_file, _message), do: :ok
  defp log_to_file(true, _log_file, nil), do: :ok

  defp log_to_file(true, log_file, message) do
    message = IO.ANSI.format_fragment(message, false)
    IO.write(log_file, [message, "\n"])
  end

  @spec log_stdout_puts(ansidata()) :: :ok
  defp log_stdout_puts(message) do
    message |> IO.ANSI.format() |> IO.puts()
    :ok
  end

  @spec get_log_file(State.job(), State.t()) :: nil | File.io_device()
  defp get_log_file(_job, %State{logs_to_file: false}), do: nil
  defp get_log_file(job_id, %State{} = state), do: state.job_to_log_file[job_id]

  @spec set_log_file(State.job(), State.t()) :: State.t()
  defp set_log_file(job_id, %State{} = state) do
    File.mkdir_p!(state.logs_dir)
    file = File.open!(Path.join(state.logs_dir, "#{job_id}.txt"), [:utf8, :write])
    put_in(state.job_to_log_file[job_id], file)
  end
end

# coveralls-ignore-stop
