defmodule Dask.Exec do
  alias Dask.{Job, JobExec, Limiter}

  @type t :: %__MODULE__{graph: :digraph.graph(), task: Task.t()}
  @enforce_keys [:graph, :task]
  defstruct [:graph, :task]

  @spec exec(:digraph.graph(), Job.t(), Limiter.t()) :: {:error, Job.upstream_results()} | {:ok, Job.upstream_results()}
  def exec(graph, %Job{} = end_job, limiter) do
    :digraph_utils.topsort(graph)
    |> Enum.reverse()
    |> Enum.reduce(%{}, fn job, job_to_task_map ->
      task = async_workflow_job_task(graph, job, job_to_task_map, limiter)
      Map.put(job_to_task_map, job, task)
    end)
    |> Map.fetch!(end_job)
    |> Task.await(:infinity)
    |> case do
      {:job_ok, res} -> {:ok, res}
      error_reason -> {:error, error_reason}
    end
  end

  @spec async_workflow_job_task(:digraph.graph(), Job.t(), %{Job.t() => Task.t()}, Limiter.t()) :: Task.t()
  defp async_workflow_job_task(graph, %Job{} = job, job_to_task_map, limiter) do
    upstream_job_id_set = :digraph.in_neighbours(graph, job) |> MapSet.new(& &1.id)
    downstream_job_pid_set = :digraph.out_neighbours(graph, job) |> MapSet.new(&job_to_task_map[&1].pid)

    Task.async(fn -> JobExec.exec(job, limiter, upstream_job_id_set, downstream_job_pid_set, %{}) end)
  end
end
