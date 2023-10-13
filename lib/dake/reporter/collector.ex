defmodule Dake.Reporter.Collector do
  defstruct [:job_id]

  @type t :: %__MODULE__{
          job_id: String.t()
        }
end

defimpl Collectable, for: Dake.Reporter.Collector do
  alias Dake.Reporter
  require Dake.Reporter.Status

  @typep collector_fn :: (any(), :done | :halt | {:cont, any()} -> :ok | Reporter.Collector.t())

  @spec into(Reporter.Collector.t()) :: {Reporter.Collector.t(), collector_fn()}
  def into(%Reporter.Collector{job_id: job_id} = original) do
    collector_fun = fn
      _, {:cont, log_message} ->
        log_message
        |> String.split(~r/\R/)
        |> Enum.each(&Reporter.job_report(job_id, Reporter.Status.log(), &1, nil))

        original

      _, :done ->
        original

      _, :halt ->
        :ok
    end

    {original, collector_fun}
  end
end
