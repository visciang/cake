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
            args: [Cake.Parser.Target.Container.Arg.t()]
          }
  end

  defmodule DevShell do
    # `@devshell`

    defstruct []

    @type t :: %__MODULE__{}
  end

  defmodule When do
    # `@when <condition>`

    @enforce_keys [:condition]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            condition: String.t()
          }
  end
end
