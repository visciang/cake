defmodule Dake.Reporter do
  use GenServer

  alias Dake.Const
  alias Dake.Reporter.{Collector, Report, Status}

  require Dake.Const
  require Dake.Reporter.Status

  @name __MODULE__

  @time_unit :millisecond
  @time_unit_scale 0.001

  defmodule State do
    @moduledoc false

    @enforce_keys [:logs_to_file, :logs_dir, :job_id_to_log_file, :start_time, :success_jobs, :failed_jobs]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            logs_to_file: boolean(),
            logs_dir: Path.t(),
            job_id_to_log_file: %{String.t() => File.io_device()},
            start_time: integer(),
            failed_jobs: MapSet.t(String.t()),
            success_jobs: MapSet.t(String.t())
          }
  end

  @spec start_link :: :ok
  def start_link do
    {:ok, _pid} = GenServer.start_link(__MODULE__, [start_time: time()], name: @name)
    :ok
  end

  @spec stop(:ok | {:error, reason :: term()} | :timeout) :: :ok
  def stop(workflow_status) do
    GenServer.call(@name, {:stop, workflow_status}, :infinity)
  end

  @spec logs(boolean()) :: :ok
  def logs(enabled) do
    GenServer.call(@name, {:logs, enabled}, :infinity)
  end

  @spec logs_to_file(boolean()) :: :ok
  def logs_to_file(enabled) do
    GenServer.call(@name, {:logs_to_file, enabled}, :infinity)
  end

  @spec job_report(String.t(), Status.t(), nil | String.t(), nil | non_neg_integer()) :: :ok
  def job_report(job_id, status, description, elapsed) do
    report? = status != Status.log() or :ets.lookup_element(@name, :logs_enabled, 2)

    if report? do
      report = %Report{job_id: job_id, status: status, description: description, elapsed: elapsed}
      GenServer.call(@name, report, :infinity)
    else
      :ok
    end
  end

  @spec time :: integer()
  def time do
    System.monotonic_time(@time_unit)
  end

  @spec collector(String.t()) :: Collectable.t()
  def collector(job_id) do
    %Collector{job_id: job_id}
  end

  @impl true
  @spec init(start_time: integer()) :: {:ok, Dake.Reporter.State.t()}
  def init(start_time: start_time) do
    :ets.new(@name, [:named_table])

    {:ok,
     %State{
       logs_to_file: false,
       logs_dir: Path.join(Const.log_dir(), to_string(DateTime.utc_now())),
       job_id_to_log_file: %{},
       start_time: start_time,
       success_jobs: MapSet.new(),
       failed_jobs: MapSet.new()
     }}
  end

  @impl true
  def handle_call(
        %Report{job_id: job_id, status: status, description: description, elapsed: elapsed},
        _from,
        %State{} = state
      ) do
    {state, log_file} = log_file(state, job_id)
    state = track_jobs(job_id, status, state)

    {status_icon, status_info} = status_icon_info(status)
    job_id = if status == Status.log(), do: [:yellow, job_id, :reset], else: job_id
    duration = if elapsed != nil, do: " (#{delta_time_string(elapsed)}) ", else: ""

    if description == nil do
      ansidata = [status_icon, " - ", :bright, job_id, :reset, "  ", duration, " ", :faint, "", :reset]
      log_puts(log_file, ansidata)
    else
      description
      |> String.split(~r/\R/)
      |> Enum.each(fn line ->
        line = "| #{line}"
        ansidata = [status_icon, " - ", :bright, job_id, :reset, "  ", duration, " ", :faint, line, :reset]
        log_puts(log_file, ansidata)
      end)
    end

    if status_info not in [nil, ""], do: log_puts(log_file, "  - #{status_info}")

    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:logs, enabled}, _from, %State{} = state) do
    :ets.insert(@name, {:logs_enabled, enabled})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:logs_to_file, enabled}, _from, %State{} = state) do
    if enabled, do: File.mkdir_p!(state.logs_dir)

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
        :ok -> [:green, "Completed (#{MapSet.size(state.success_jobs)} jobs)", :reset]
        {:error, _} -> [:red, "Failed jobs:", :reset, Enum.map(Enum.sort(state.failed_jobs), &"\n- #{&1}"), "\n"]
        :timeout -> [:red, "Timeout", :reset]
      end

    duration = delta_time_string(end_time - state.start_time)

    log_stdout_puts(["\n", end_message, " (#{duration})\n"])

    {:stop, :normal, :ok, state}
  end

  @spec track_jobs(String.t(), Status.t(), State.t()) :: State.t()
  defp track_jobs(job_id, status, %State{} = state) do
    case status do
      Status.error(_reason, _stacktrace) -> update_in(state.failed_jobs, &MapSet.put(&1, job_id))
      Status.ok() -> update_in(state.success_jobs, &MapSet.put(&1, job_id))
      _ -> state
    end
  end

  @spec delta_time_string(number()) :: String.t()
  defp delta_time_string(elapsed) do
    Dask.Utils.seconds_to_compound_duration(elapsed * @time_unit_scale)
  end

  @spec status_icon_info(Status.t()) :: {IO.chardata(), nil | IO.chardata()}
  defp status_icon_info(status) do
    case status do
      Status.ok() ->
        {[:green, "✔", :reset], nil}

      Status.error(reason, stacktrace) ->
        reason_str = if is_binary(reason), do: reason, else: inspect(reason)
        reason_str = if stacktrace != nil, do: [reason_str, "\n", stacktrace], else: reason_str
        {[:red, "✘", :reset], reason_str}

      Status.timeout() ->
        {"⏰", nil}

      Status.log() ->
        {".", nil}
    end
  end

  @spec log_puts(nil | File.io_device(), IO.ANSI.ansidata()) :: :ok
  defp log_puts(log_file, message) do
    log_stdout_puts(message)

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

  @spec log_file(State.t(), String.t()) :: {State.t(), nil | File.io_device()}
  defp log_file(%State{logs_to_file: false} = state, _job_id) do
    {state, nil}
  end

  defp log_file(%State{job_id_to_log_file: job_id_to_log_file} = state, job_id)
       when is_map_key(job_id_to_log_file, job_id) do
    {state, job_id_to_log_file[job_id]}
  end

  defp log_file(%State{} = state, job_id) do
    file = File.open!(Path.join(state.logs_dir, "#{job_id}.txt"), [:utf8, :write])
    state = update_in(state.job_id_to_log_file, &Map.put(&1, job_id, file))
    {state, file}
  end
end
