defmodule Dake.Reporter.Report do
  @enforce_keys [:job_id, :job_ns, :status, :description, :elapsed]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          job_id: String.t(),
          job_ns: String.t(),
          status: Dake.Reporter.Status.t(),
          description: nil | String.t(),
          elapsed: nil | non_neg_integer()
        }
end
