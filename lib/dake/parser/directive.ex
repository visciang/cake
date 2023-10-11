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
end
