defmodule Dake.Reporter.Report do
  @enforce_keys [:job_id, :status, :description, :elapsed]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          job_id: String.t(),
          status: Dake.Reporter.Status.t(),
          description: nil | String.t(),
          elapsed: nil | non_neg_integer()
        }
end
