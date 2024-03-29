defmodule Dask.JobExec do
  require Logger
  alias Dask.{Job, Limiter}

  @spec exec(Job.t(), Limiter.t(), MapSet.t(Job.id()), MapSet.t(pid()), Job.upstream_results()) :: Job.job_exec_result()
  def exec(%Job{} = job, limiter, upstream_job_id_set, downstream_job_pid_set, upstream_jobs_status) do
    if MapSet.size(upstream_job_id_set) == 0 do
      Logger.debug("START #{inspect(job.id)}  upstream_jobs_status: #{inspect(upstream_jobs_status)}")

      job_status = timed(fn -> exec_job_fun(job, limiter, upstream_jobs_status, job.id) end, job.timeout)
      job.on_exit.(job.id, upstream_jobs_status, job_status)

      for downstream_job_pid <- downstream_job_pid_set,
          do: send(downstream_job_pid, {job.id, job_status})

      Logger.debug("END #{inspect(job.id)} status: #{inspect(job_status)}")

      job_status
    else
      wait_upstream_job_task(job, limiter, upstream_job_id_set, downstream_job_pid_set, upstream_jobs_status)
    end
  end

  @spec exec_job_fun(Job.t(), Limiter.t(), Job.upstream_results(), Job.id()) :: Job.job_exec_result()
  defp exec_job_fun(%Job{} = job, limiter, upstream_jobs_status, job_id) do
    if Enum.all?(Map.values(upstream_jobs_status), &match?({:job_ok, _}, &1)) do
      try do
        upstream_jobs_result =
          upstream_jobs_status
          |> Map.new(fn {upstream_job_id, {_, upstream_job_result}} -> {upstream_job_id, upstream_job_result} end)

        Limiter.wait_my_turn(limiter, job_id)

        job.fun.(job.id, upstream_jobs_result)
      rescue
        job_error -> {:job_error, job_error, Exception.format(:error, job_error, __STACKTRACE__)}
      else
        job_result -> {:job_ok, job_result}
      end
    else
      :job_skipped
    end
  end

  @spec wait_upstream_job_task(Job.t(), Limiter.t(), MapSet.t(pid()), MapSet.t(pid()), Job.upstream_results()) ::
          Job.job_exec_result()
  defp wait_upstream_job_task(job, limiter, upstream_job_id_set, downstream_job_pid_set, upstream_jobs_status) do
    receive do
      {upstream_job_id, upstream_job_status} ->
        upstream_job_id_set = MapSet.delete(upstream_job_id_set, upstream_job_id)
        upstream_jobs_status = Map.put(upstream_jobs_status, upstream_job_id, upstream_job_status)
        exec(job, limiter, upstream_job_id_set, downstream_job_pid_set, upstream_jobs_status)
    end
  end

  @spec timed((-> Job.job_exec_result()), timeout()) :: Job.result()
  defp timed(fun, timeout) do
    task = Task.async(fun)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> :job_timeout
    end
  end
end
