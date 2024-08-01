# coveralls-ignore-start

defmodule Cake.Reporter.Plain.State do
  defstruct []
  @type t :: %__MODULE__{}
end

defmodule Cake.Reporter.Plain do
  @behaviour Cake.Reporter

  alias Cake.Reporter
  alias Cake.Reporter.Plain.State
  alias Cake.Reporter.{Icon, Status}

  require Cake.Reporter.Status

  @typep ansidata :: IO.ANSI.ansidata()

  @impl Reporter
  def init do
    %State{}
  end

  @impl Reporter
  def job_start(job_id, %State{} = state) do
    ansidata = report_line("+", [:faint, job_id, :reset], nil, " | #{DateTime.utc_now(:second)}")
    ansi_puts(ansidata)

    {ansidata, state}
  end

  @impl Reporter
  def job_end(job_id, status, duration, %State{} = state) do
    {job_id, status_icon, status_info} =
      case status do
        Status.ok() ->
          {[:green, job_id, :reset], Icon.ok(), nil}

        Status.error(reason, stacktrace) ->
          reason_str = if is_binary(reason), do: reason, else: inspect(reason)
          reason_str = if stacktrace != nil, do: [reason_str, "\n", stacktrace], else: reason_str
          {[:red, job_id, :reset], Icon.error(), reason_str}

        Status.timeout() ->
          {[:red, job_id, :reset], Icon.timeout(), nil}
      end

    ansidata = report_line(status_icon, job_id, duration, " | #{DateTime.utc_now(:second)}")

    ansidata =
      if status_info == nil do
        ansidata
      else
        [ansidata, "\n   #{status_info}"]
      end

    ansi_puts(ansidata)

    {ansidata, state}
  end

  @impl Reporter
  def job_log(job_id, msg, %State{} = state) do
    ansidata = report_line(Icon.log(), job_id, nil, " | #{msg}")
    ansi_puts(ansidata)

    {ansidata, state}
  end

  @impl Reporter
  def job_notice(job_id, msg, %State{} = state) do
    ansidata = report_line(Icon.notice(), job_id, nil, " | #{msg}")
    ansi_puts(ansidata)

    {ansidata, state}
  end

  @impl Reporter
  def job_output(job_id, output, %State{} = state) do
    job_id = [:yellow, job_id, :reset]

    ansidata = report_line(Icon.output(), job_id, nil, " | output: #{output}")
    ansi_puts(ansidata)

    {ansidata, state}
  end

  @impl Reporter
  def job_shell_start(job, %State{} = state) do
    job_notice(job, "Starting interactive shell\n", state)
  end

  @impl Reporter
  def job_shell_end(_job, %State{} = state) do
    {nil, state}
  end

  @impl Reporter
  def info({__MODULE__, _}, %State{} = state) do
    {nil, state}
  end

  @spec ansi_puts(ansidata()) :: :ok
  defp ansi_puts(message) do
    IO.puts(IO.ANSI.format_fragment(message))
  end

  @spec report_line(
          status_icon :: ansidata(),
          job_id :: ansidata(),
          duration :: nil | ansidata(),
          description :: String.t()
        ) :: ansidata()
  defp report_line(status_icon, job_id, duration, description) do
    line = [status_icon, :reset, "  ", :bright, job_id, :reset]
    line = [line, :faint, "  ", String.replace_invalid(description), :reset]
    line = if duration, do: [line, ["   (#{duration})  "]], else: line

    line
  end
end

# coveralls-ignore-stop
