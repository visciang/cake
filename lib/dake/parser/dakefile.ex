defmodule Dake.Parser.Dakefile do
  @moduledoc """
  Dakefile.
  """

  @enforce_keys [:includes, :args, :targets]
  defstruct @enforce_keys

  @type target :: Dake.Parser.Target.Docker.t() | Dake.Parser.Target.Alias.t()

  @type t :: %__MODULE__{
          includes: [Dake.Parser.Docker.Command.t()],
          args: [Dake.Parser.Docker.Arg.t()],
          targets: [target()]
        }
end
