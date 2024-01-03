defmodule Cake.Reporter.Interactive.State do
  defstruct jobs: %{}, spinner_frame_idx: 0

  @type t :: %__MODULE__{
          jobs: %{String.t() => %{start: integer(), outputs: [Path.t()]}},
          spinner_frame_idx: non_neg_integer()
        }
end

defmodule Cake.Reporter.Interactive do
  @behaviour Cake.Reporter

  alias Cake.Reporter
  alias Cake.Reporter.Interactive.State

  require Cake.Reporter.Status

  @render_period_ms 100
  @spinner_frames %{
    0 => "⠋",
    1 => "⠙",
    2 => "⠹",
    3 => "⠸",
    4 => "⠼",
    5 => "⠴",
    6 => "⠦",
    7 => "⠧",
    8 => "⠇",
    9 => "⠏"
  }

  def init do
    schedule_render_spinner()

    %State{}
  end

  def job_start(job, %State{} = state) do
    state = put_in(state.jobs[job], %{start: System.monotonic_time(), outputs: []})
    state = render_spinner(state)

    {nil, state}
  end

  def job_end(job, status, duration, %State{} = state) do
    ansidata = render_job_end(job, status, state.jobs[job].outputs, duration)

    {_, state} = pop_in(state.jobs[job])
    state = render_spinner(state)

    {ansidata, state}
  end

  def job_log(_job, msg, %State{} = state) do
    {msg, state}
  end

  def job_notice(_job, msg, %State{} = state) do
    {msg, state}
  end

  def job_output(job, output_path, %State{} = state) do
    state = update_in(state.jobs[job].outputs, &[output_path | &1])

    {nil, state}
  end

  def info({__MODULE__, :render_spinner}, %State{} = state) do
    state = render_spinner(state)
    schedule_render_spinner()

    state
  end

  @spec render_job_end(
          Reporter.State.job(),
          status :: Reporter.Status.t(),
          outputs :: [Path.t()],
          duration :: String.t()
        ) :: IO.ANSI.ansidata()
  defp render_job_end({job_ns, job_id}, status, outputs, duration) do
    job_ns = job_ns_to_string(job_ns)

    {job_id, status_icon} =
      case status do
        Reporter.Status.ok() ->
          {[:green, job_id, :reset], [:green, "✔", :reset]}

        Reporter.Status.error(_reason, _stacktrace) ->
          {[:red, job_id, :reset], [:red, "✘", :reset]}

        Reporter.Status.timeout() ->
          {[:red, job_id, :reset], "⏰"}
      end

    outputs_ansidata =
      for output <- outputs do
        ["\n  ", :yellow, "←", :reset, " ", output]
      end

    ansidata = [
      ["\r", :clear_line],
      [status_icon, " ", :faint, job_ns, :reset, :bright, job_id, :reset, " (#{duration})", outputs_ansidata]
    ]

    IO.puts(IO.ANSI.format_fragment(ansidata))

    ansidata
  end

  defp render_spinner(%State{jobs: jobs} = state) when map_size(jobs) == 0, do: state

  defp render_spinner(%State{} = state) do
    spinner_frame = Map.fetch!(@spinner_frames, state.spinner_frame_idx)

    running_jobs =
      state.jobs
      |> Enum.sort_by(fn {_job, %{start: start}} -> start end)
      |> Enum.map_join(" | ", fn {{job_ns, job_id}, _} ->
        "#{job_ns_to_string(job_ns)}#{job_id}"
      end)

    ["\r", :clear_line, :blue, spinner_frame, :reset, " ", running_jobs]
    |> IO.ANSI.format()
    |> IO.write()

    next_spinner_frame_idx = rem(state.spinner_frame_idx + 1, map_size(@spinner_frames))
    put_in(state.spinner_frame_idx, next_spinner_frame_idx)
  end

  @spec schedule_render_spinner :: :ok
  defp schedule_render_spinner do
    Process.send_after(self(), {__MODULE__, :render_spinner}, @render_period_ms)
    :ok
  end

  @spec job_ns_to_string([String.t()]) :: IO.ANSI.ansidata()
  defp job_ns_to_string([]), do: []
  defp job_ns_to_string(job_ns), do: ["(", Enum.join(job_ns, ", "), ") "]
end
