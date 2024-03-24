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
  def job_start({job_ns, job_id}, %State{} = state) do
    ansidata = report_line("+", job_ns, [:faint, job_id, :reset], nil, nil)
    ansi_puts(ansidata)

    {ansidata, state}
  end

  @impl Reporter
  def job_end({job_ns, job_id}, status, duration, %State{} = state) do
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

    ansidata = report_line(status_icon, job_ns, job_id, duration, nil)

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
  def job_log({job_ns, job_id}, msg, %State{} = state) do
    ansidata = report_line(Icon.log(), job_ns, job_id, nil, " | #{msg}")
    ansi_puts(ansidata)

    {ansidata, state}
  end

  @impl Reporter
  def job_notice({job_ns, job_id}, msg, %State{} = state) do
    ansidata = report_line(Icon.notice(), job_ns, job_id, nil, " | #{msg}")
    ansi_puts(ansidata)

    {ansidata, state}
  end

  @impl Reporter
  def job_output({job_ns, job_id}, output, %State{} = state) do
    job_id = [:yellow, job_id, :reset]

    ansidata = report_line(Icon.output(), job_ns, job_id, nil, " | output: #{output}")
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
          job_ns :: [String.t()],
          job_id :: ansidata(),
          duration :: nil | ansidata(),
          description :: nil | String.t()
        ) :: ansidata()
  defp report_line(status_icon, job_ns, job_id, duration, description) do
    job_ns = if job_ns == [], do: "", else: ["(", Enum.join(job_ns, ", "), ") "]
    line = [status_icon, :reset, "  ", :faint, job_ns, :reset, :bright, job_id, :reset]
    line = if duration, do: [line, ["   (#{duration})  "]], else: line

    line =
      if description do
        description = String.replace_invalid(description)
        [line, :faint, "  ", description, :reset]
      else
        line
      end

    line
  end
end

# coveralls-ignore-stop
