defmodule Dake.Parser.Dakefile do
  @moduledoc """
  Dakefile.
  """

  defmodule Include do
    @moduledoc """
    `@include <path> [<arg>, ...]`.
    """

    @enforce_keys [:path]
    defstruct @enforce_keys ++ [args: []]

    @type t :: %__MODULE__{
            path: Path.t(),
            args: [Dake.Parser.Docker.Arg.t()]
          }
  end

  @enforce_keys [:includes, :args, :targets]
  defstruct @enforce_keys

  @type target :: Dake.Parser.Target.Docker.t() | Dake.Parser.Target.Alias.t()

  @type t :: %__MODULE__{
          includes: [Include.t()],
          args: [Dake.Parser.Docker.Arg.t()],
          targets: [target()]
        }
end
