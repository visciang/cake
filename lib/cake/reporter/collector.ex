# coveralls-ignore-start

defmodule Cake.Reporter.Collector do
  @enforce_keys [:job_id, :type]
  defstruct @enforce_keys

  @type report_type :: :log | :info

  @type t :: %__MODULE__{
          job_id: String.t(),
          type: report_type()
        }
end

defimpl Collectable, for: Cake.Reporter.Collector do
  alias Cake.Reporter
  require Cake.Reporter.Status

  @typep collector_fn :: (any(), :done | :halt | {:cont, any()} -> :ok | Reporter.Collector.t())

  @spec into(Reporter.Collector.t()) :: {Reporter.Collector.t(), collector_fn()}
  def into(%Reporter.Collector{} = collector) do
    collector_fun = fn
      _, {:cont, message} ->
        case collector.type do
          :log ->
            Reporter.job_log(collector.job_id, message)

          :info ->
            Reporter.job_notice(collector.job_id, message)
        end

        collector

      _, :done ->
        collector

      _, :halt ->
        :ok
    end

    {collector, collector_fun}
  end
end

# coveralls-ignore-stop
