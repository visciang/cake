defmodule Cake.Reporter.State do
  alias Cake.Reporter
  alias Cake.Reporter.Status

  @enforce_keys [
    :reporter,
    :logs_to_file,
    :logs_dir,
    :job_id_to_log_file,
    :start_time,
    :track,
    :reporter_state
  ]
  defstruct @enforce_keys

  @type job :: {job_ns :: [String.t()], job_id :: String.t()}
  @type job_status :: %{job() => Status.t() | {:running, start_time :: integer()}}

  @type t :: %__MODULE__{
          reporter: Reporter.behaviour(),
          logs_to_file: boolean(),
          logs_dir: Path.t(),
          job_id_to_log_file: %{job() => File.io_device()},
          start_time: integer(),
          track: job_status(),
          reporter_state: term()
        }
end

defmodule Cake.Reporter do
  use GenServer

  alias Cake.{Dir, Reporter, Type}
  alias Cake.Reporter.{Collector, Duration, State, Status}

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

  @spec job_start([String.t()], String.t()) :: :ok
  def job_start(job_ns, job_id) do
    GenServer.cast(@name, {:job_start, {job_ns, job_id}})
  end

  @spec job_end([String.t()], String.t(), Status.t()) :: :ok
  def job_end(job_ns, job_id, status) do
    GenServer.cast(@name, {:job_end, {job_ns, job_id}, status})
  end

  @spec job_notice([String.t()], String.t(), String.t()) :: :ok
  def job_notice(job_ns, job_id, message) do
    GenServer.cast(@name, {:job_notice, {job_ns, job_id}, message})
  end

  @spec job_log([String.t()], String.t(), String.t()) :: :ok
  def job_log(job_ns, job_id, message) do
    GenServer.cast(@name, {:job_log, {job_ns, job_id}, message})
  end

  @spec job_output([String.t()], String.t(), Path.t()) :: :ok
  def job_output(job_ns, job_id, output_path) do
    GenServer.cast(@name, {:job_output, {job_ns, job_id}, output_path})
  end

  @spec collector([String.t()], String.t(), Collector.report_type()) :: Collectable.t()
  def collector(job_ns, job_id, type) do
    %Collector{job_ns: job_ns, job_id: job_id, type: type}
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
        job_id_to_log_file: %{},
        start_time: Duration.time(),
        track: %{},
        reporter_state: reporter.init()
      }

    {:ok, state}
  end

  @impl GenServer
  def handle_cast({:job_start, job}, %State{} = state) do
    state = set_log_file(job, state)
    log_file = get_log_file(job, state)

    {ansidata, reporter_state} = state.reporter.job_start(job, state.reporter_state)
    log_to_file(state.logs_to_file, log_file, ansidata)

    state = put_in(state.track[job], {:running, Duration.time()})
    state = put_in(state.reporter_state, reporter_state)

    {:noreply, state}
  end

  def handle_cast({:job_end, job, status}, %State{} = state) do
    log_file = get_log_file(job, state)

    duration = job_duration(job, state)
    {ansidata, reporter_state} = state.reporter.job_end(job, status, duration, state.reporter_state)
    log_to_file(state.logs_to_file, log_file, ansidata)

    state = put_in(state.track[job], status)
    state = put_in(state.reporter_state, reporter_state)

    {:noreply, state}
  end

  def handle_cast({:job_log, job, message}, %State{} = state) do
    log_file = get_log_file(job, state)

    reporter_state =
      for line <- String.split(message, ~r/\R/), reduce: state.reporter_state do
        reporter_state ->
          {ansidata, reporter_state} = state.reporter.job_log(job, line, reporter_state)
          log_to_file(state.logs_to_file, log_file, ansidata)

          reporter_state
      end

    state = put_in(state.reporter_state, reporter_state)

    {:noreply, state}
  end

  def handle_cast({:job_notice, job, message}, %State{} = state) do
    reporter_state =
      for line <- String.split(message, ~r/\R/), reduce: state.reporter_state do
        reporter_state ->
          {_ansidata, reporter_state} = state.reporter.job_notice(job, line, reporter_state)

          reporter_state
      end

    state = put_in(state.reporter_state, reporter_state)

    {:noreply, state}
  end

  def handle_cast({:job_output, job, output_path}, %State{} = state) do
    log_file = get_log_file(job, state)

    {ansidata, reporter_state} = state.reporter.job_output(job, output_path, state.reporter_state)
    log_to_file(state.logs_to_file, log_file, ansidata)

    state = put_in(state.reporter_state, reporter_state)

    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:stop, workflow_status}, _from, %State{} = state) do
    if state.logs_to_file do
      log_stdout_puts("\nLogs directory: #{state.logs_dir}")

      for {_job_id, file} <- state.job_id_to_log_file do
        File.close(file)
      end
    end

    end_message = end_message(workflow_status, state.track)

    if end_message do
      duration = Duration.delta_time_string(Duration.time() - state.start_time)
      log_stdout_puts(["\n", end_message, " (#{duration})\n"])
    end

    {:stop, :normal, :ok, state}
  end

  @impl GenServer
  def handle_info({reporter, _} = info, %State{reporter: reporter} = state) do
    reporter_state = reporter.info(info, state.reporter_state)
    state = put_in(state.reporter_state, reporter_state)

    {:noreply, state}
  end

  @spec end_message(Cake.Cmd.result(), State.job_status()) :: ansidata()
  defp end_message(workflow_status, jobs_status) do
    case workflow_status do
      :ok ->
        count = Enum.count(Map.values(jobs_status), &(&1 == :ok))
        [:green, "Completed (#{count} jobs)", :reset]

      {:ignore, _} ->
        nil

      {:error, _} ->
        failed =
          for {{job_ns, job_id}, status} <- jobs_status,
              match?(Status.error(_, _), status) or match?(Status.timeout(), status) do
            if job_ns == [] do
              "- #{job_id}\n"
            else
              "- (#{inspect(job_ns)}) #{job_id}\n"
            end
          end

        [:red, "Failed jobs:", "\n", failed, "\n", :reset]

      :timeout ->
        [:red, "Timeout", :reset]
    end
  end

  @spec job_duration(State.job(), State.t()) :: String.t()
  defp job_duration(job, %State{} = state) do
    end_time = Duration.time()

    start_time =
      case state.track[job] do
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
  defp get_log_file(job, %State{} = state), do: state.job_id_to_log_file[job]

  @spec set_log_file(State.job(), State.t()) :: State.t()
  defp set_log_file({job_ns, job_id} = job, %State{} = state) do
    File.mkdir_p!(state.logs_dir)
    file = File.open!(Path.join(state.logs_dir, "#{inspect(job_ns)}-#{job_id}.txt"), [:utf8, :write])
    put_in(state.job_id_to_log_file[job], file)
  end
end
