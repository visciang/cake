defmodule Cake.Reporter.Duration do
  @time_unit :millisecond

  @spec time :: integer()
  def time do
    System.monotonic_time(@time_unit)
  end

  @spec delta_time_string(elapsed_ms :: number()) :: String.t()
  def delta_time_string(elapsed_ms) do
    Dask.Utils.seconds_to_compound_duration(elapsed_ms / 1_000)
  end
end
