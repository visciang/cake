defmodule Dake.Parser.Dakefile do
  defmodule Include do
    # `@include <ref> [<arg>, ...]`.

    @enforce_keys [:ref]
    defstruct @enforce_keys ++ [args: []]

    @type t :: %__MODULE__{
            ref: String.t(),
            args: [Dake.Parser.Docker.Arg.t()]
          }
  end

  defstruct includes: [], args: [], targets: []

  @type target :: Dake.Parser.Target.Docker.t() | Dake.Parser.Target.Alias.t()

  @type t :: %__MODULE__{
          includes: [Include.t()],
          args: [Dake.Parser.Docker.Arg.t()],
          targets: [target()]
        }
end
