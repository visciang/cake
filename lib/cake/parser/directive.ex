defmodule Cake.Parser.Directive do
  defmodule Output do
    # `@output <path>`

    @enforce_keys [:path]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            path: Path.t()
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
            args: [Cake.Parser.Container.Arg.t()]
          }
  end

  defmodule Import do
    # `@import [--ouput] [--push] --as=<as> <ref> <target> [<arg>, ...]`.

    @enforce_keys [:ref, :target, :as]
    defstruct @enforce_keys ++ [output: false, push: false, args: []]

    @type t :: %__MODULE__{
            ref: String.t(),
            target: String.t(),
            as: String.t(),
            output: boolean(),
            push: boolean(),
            args: [Cake.Parser.Container.Arg.t()]
          }
  end

  defmodule DevShell do
    # `@devshell`

    defstruct []

    @type t :: %__MODULE__{}
  end
end
