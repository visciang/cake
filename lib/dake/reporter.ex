defmodule Dake.Reporter do
  use GenServer

  alias Dake.Dir
  alias Dake.Reporter.{Collector, Status}

  require Dake.Reporter.Status

  @typep ansidata :: IO.ANSI.ansidata()

  @name __MODULE__

  @time_unit :millisecond
  @time_unit_scale 0.001

  defmodule State do
    @moduledoc false

    @enforce_keys [:verbose, :logs_to_file, :logs_dir, :job_id_to_log_file, :start_time, :track]
    defstruct @enforce_keys

    @type job :: {job_ns :: [String.t()], job_id :: String.t()}

    @type t :: %__MODULE__{
            verbose: boolean(),
            logs_to_file: boolean(),
            logs_dir: Path.t(),
            job_id_to_log_file: %{job() => File.io_device()},
            start_time: integer(),
            track: %{job() => Status.t() | {:running, start_time :: integer()}}
          }
  end

  @spec start_link :: :ok
  def start_link do
    {:ok, _pid} = GenServer.start_link(__MODULE__, [], name: @name)
    :ok
  end

  @spec stop(:ok | {:error, reason :: term()} | :timeout) :: :ok
  def stop(workflow_status) do
    GenServer.call(@name, {:stop, workflow_status}, :infinity)
  end

  @spec verbose(boolean()) :: :ok
  def verbose(enabled) do
    GenServer.call(@name, {:verbose, enabled}, :infinity)
    :ok
  end

  @spec logs_to_file(boolean()) :: :ok
  def logs_to_file(enabled) do
    GenServer.call(@name, {:logs_to_file, enabled})
    :ok
  end

  @spec job_start([String.t()], String.t()) :: :ok
  def job_start(job_ns, job_id) do
    GenServer.cast(@name, {:job_start, {job_ns, job_id}})
  end

  @spec job_end([String.t()], String.t(), Status.t()) :: :ok
  def job_end(job_ns, job_id, status) do
    GenServer.cast(@name, {:job_end, {job_ns, job_id}, status})
  end

  @spec job_log([String.t()], String.t(), String.t()) :: :ok
  def job_log(job_ns, job_id, message) do
    GenServer.cast(@name, {:job_log, {job_ns, job_id}, message})
  end

  @spec job_output([String.t()], String.t(), Path.t()) :: :ok
  def job_output(job_ns, job_id, output_path) do
    GenServer.cast(@name, {:job_output, {job_ns, job_id}, output_path})
  end

  @spec time :: integer()
  def time do
    System.monotonic_time(@time_unit)
  end

  @spec collector([String.t()], String.t()) :: Collectable.t()
  def collector(job_ns, job_id) do
    %Collector{job_ns: job_ns, job_id: job_id}
  end

  @impl true
  @spec init([]) :: {:ok, Dake.Reporter.State.t()}
  def init([]) do
    {:ok,
     %State{
       verbose: false,
       logs_to_file: false,
       logs_dir: Path.join(Dir.log(), to_string(DateTime.utc_now())),
       job_id_to_log_file: %{},
       start_time: time(),
       track: %{}
     }}
  end

  @impl true
  def handle_cast({:job_start, {job_ns, job_id} = job}, %State{} = state) do
    {state, log_file} = log_file(state, job)

    ansidata = report_line("+", job_ns, [:faint, job_id, :reset], nil, nil)
    log_puts(log_file, ansidata, true)

    state = put_in(state.track[job], {:running, time()})

    {:noreply, state}
  end

  def handle_cast({:job_end, {job_ns, job_id} = job, status}, %State{} = state) do
    {state, log_file} = log_file(state, job)

    {job_id, status_icon, status_info} =
      case status do
        Status.ok() ->
          {[:green, job_id, :reset], [:green, "✔", :reset], nil}

        Status.error(reason, stacktrace) ->
          reason_str = if is_binary(reason), do: reason, else: inspect(reason)
          reason_str = if stacktrace != nil, do: [reason_str, "\n", stacktrace], else: reason_str
          {[:red, job_id, :reset], [:red, "✘", :reset], reason_str}

        Status.timeout() ->
          {[:red, job_id, :reset], "⏰", nil}
      end

    end_time = time()

    start_time =
      case Map.get(state.track, job) do
        {:running, start_time} -> start_time
        _ -> end_time
      end

    duration = " (#{delta_time_string(end_time - start_time)}) "

    ansidata = report_line(status_icon, job_ns, job_id, duration, nil)
    log_puts(log_file, ansidata, true)

    if status_info not in [nil, ""] do
      log_puts(log_file, "  - #{status_info}", true)
    end

    state = put_in(state.track[job], status)

    {:noreply, state}
  end

  def handle_cast({:job_log, job, message}, %State{} = state) do
    {state, log_file} = log_file(state, {job_ns, job_id} = job)

    message
    |> String.split(~r/\R/)
    |> Enum.each(fn line ->
      ansidata = report_line(".", job_ns, job_id, nil, " | #{line}")
      log_puts(log_file, ansidata, state.verbose)
    end)

    {:noreply, state}
  end

  def handle_cast({:job_output, job, output_path}, %State{} = state) do
    {state, log_file} = log_file(state, {job_ns, job_id} = job)

    status_icon = [:yellow, "←", :reset]
    job_id = [:yellow, job_id, :reset]
    ansidata = report_line(status_icon, job_ns, job_id, nil, " | output: #{output_path}")
    log_puts(log_file, ansidata, true)

    {:noreply, state}
  end

  @impl true
  def handle_call({:verbose, enabled}, _from, %State{} = state) do
    {:reply, :ok, put_in(state.verbose, enabled)}
  end

  @impl true
  def handle_call({:logs_to_file, enabled}, _from, %State{} = state) do
    {:reply, :ok, put_in(state.logs_to_file, enabled)}
  end

  @impl true
  def handle_call({:stop, reason}, _from, %State{} = state) do
    end_time = time()

    if state.logs_to_file do
      log_stdout_puts("\nLogs directory: #{state.logs_dir}")

      state.job_id_to_log_file
      |> Map.values()
      |> Enum.each(&File.close/1)
    end

    end_message =
      case reason do
        :ok ->
          count = state.track |> Map.values() |> Enum.count(&(&1 == :ok))
          [:green, "Completed (#{count} jobs)", :reset]

        {:error, _} ->
          failed =
            state.track
            |> Enum.filter(fn {_job, status} ->
              match?(Status.error(_, _), status) or match?(Status.timeout(), status)
            end)
            |> Enum.map(fn {job, _status} ->
              "\n- #{inspect(job)}"
            end)

          [:red, "Failed jobs:", :reset, failed, "\n"]

        :timeout ->
          [:red, "Timeout", :reset]
      end

    duration = delta_time_string(end_time - state.start_time)

    log_stdout_puts(["\n", end_message, " (#{duration})\n"])

    {:stop, :normal, :ok, state}
  end

  @spec delta_time_string(number()) :: String.t()
  defp delta_time_string(elapsed) do
    Dask.Utils.seconds_to_compound_duration(elapsed * @time_unit_scale)
  end

  @spec report_line(ansidata(), [String.t()], ansidata(), nil | ansidata(), nil | ansidata()) :: ansidata()
  defp report_line(status_icon, job_ns, job_id, duration, description) do
    job_ns = if job_ns == [], do: "", else: ["(", Enum.join(job_ns, ", "), ") "]
    line = ["[", status_icon, "]  ", :faint, job_ns, :reset, :bright, job_id, :reset]
    line = if duration, do: [line, ["  #{duration} "]], else: line
    line = if description, do: [line, :faint, "  ", description, :reset], else: line
    line
  end

  @spec log_puts(nil | File.io_device(), IO.ANSI.ansidata(), boolean()) :: :ok
  defp log_puts(log_file, message, stdout?) do
    if stdout? do
      log_stdout_puts(message)
    end

    if log_file != nil do
      message = message |> List.flatten() |> Enum.reject(&is_atom(&1))
      IO.write(log_file, [message, "\n"])
    end
  end

  @spec log_stdout_puts(IO.ANSI.ansidata()) :: :ok
  defp log_stdout_puts(message) do
    message |> IO.ANSI.format() |> IO.puts()
    :ok
  end

  @spec log_file(State.t(), State.job()) :: {State.t(), nil | File.io_device()}
  defp log_file(%State{logs_to_file: false} = state, _job) do
    {state, nil}
  end

  defp log_file(%State{job_id_to_log_file: job_id_to_log_file} = state, job)
       when is_map_key(job_id_to_log_file, job) do
    {state, job_id_to_log_file[job]}
  end

  defp log_file(%State{} = state, {job_ns, job_id} = job) do
    File.mkdir_p!(state.logs_dir)
    file = File.open!(Path.join(state.logs_dir, "#{inspect(job_ns)}-#{job_id}.txt"), [:utf8, :write])
    state = put_in(state.job_id_to_log_file[job], file)
    {state, file}
  end
end
