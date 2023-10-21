defmodule Dake.Reporter.Collector do
  defstruct [:job_ns, :job_id]

  @type t :: %__MODULE__{
          job_ns: [String.t()],
          job_id: String.t()
        }
end

defimpl Collectable, for: Dake.Reporter.Collector do
  alias Dake.Reporter
  require Dake.Reporter.Status

  @typep collector_fn :: (any(), :done | :halt | {:cont, any()} -> :ok | Reporter.Collector.t())

  @spec into(Reporter.Collector.t()) :: {Reporter.Collector.t(), collector_fn()}
  def into(%Reporter.Collector{} = collector) do
    collector_fun = fn
      _, {:cont, log_message} ->
        Reporter.job_log(collector.job_ns, collector.job_id, log_message)

        collector

      _, :done ->
        collector

      _, :halt ->
        :ok
    end

    {collector, collector_fun}
  end
end
