defmodule Dake.Parser.Dakefile do
  alias Dake.Parser.Directive

  defstruct path: ".", includes: [], args: [], targets: []

  @type target :: Dake.Parser.Target.Container.t() | Dake.Parser.Target.Alias.t()

  @type t :: %__MODULE__{
          path: Path.t(),
          includes: [Directive.Include.t()],
          args: [Dake.Parser.Container.Arg.t()],
          targets: [target()]
        }
end
