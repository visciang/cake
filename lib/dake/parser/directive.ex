defmodule Dake.Parser.Directive do
  defmodule Output do
    # `@output <dir>`

    @enforce_keys [:dir]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            dir: Path.t()
          }
  end

  defmodule Push do
    # `@push`

    defstruct []

    @type t :: %__MODULE__{}
  end

  defmodule Include do
    # `@include <ref> [<arg>, ...]`.

    @enforce_keys [:ref]
    defstruct @enforce_keys ++ [args: []]

    @type t :: %__MODULE__{
            ref: String.t(),
            args: [Dake.Parser.Docker.Arg.t()]
          }
  end

  defmodule Import do
    # `@import [--ouput] [--push] <ref> <target> [<arg>, ...]`.

    @enforce_keys [:ref, :target]
    defstruct @enforce_keys ++ [output: false, push: false, args: []]

    @type t :: %__MODULE__{
            ref: String.t(),
            target: String.t(),
            output: boolean(),
            push: boolean(),
            args: [Dake.Parser.Docker.Arg.t()]
          }
  end
end
