defmodule Dask.Dot do
  alias Dask
  alias Dask.Job

  @spec export(Dask.t()) :: [String.t()]
  def export(%Dask{jobs: jobs}) do
    ["strict digraph {\n", Enum.flat_map(Map.values(jobs), &job_edge/1), "}\n"]
  end

  @spec job_edge(Job.t()) :: [String.t()]
  defp job_edge(%Job{} = job) do
    if MapSet.size(job.downstream_jobs) == 0 do
      [~s/#{inspect(job.id)}\n/]
    else
      for downstream_job <- job.downstream_jobs,
          do: ~s/#{inspect(job.id)} -> #{inspect(downstream_job)}\n/
    end
  end
end
