defmodule Dake.Reporter.Collector do
  defstruct [:job_id, :job_ns]

  @type t :: %__MODULE__{
          job_id: String.t(),
          job_ns: String.t()
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
        Reporter.job_report(collector.job_id, collector.job_ns, Reporter.Status.log(), log_message, nil)

        collector

      _, :done ->
        collector

      _, :halt ->
        :ok
    end

    {collector, collector_fun}
  end
end
