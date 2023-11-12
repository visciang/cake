defmodule Cake.Parser.Dakefile do
  alias Cake.Parser.Directive

  defstruct path: ".", includes: [], args: [], targets: []

  @type target :: Cake.Parser.Target.Container.t() | Cake.Parser.Target.Alias.t()

  @type t :: %__MODULE__{
          path: Path.t(),
          includes: [Directive.Include.t()],
          args: [Cake.Parser.Container.Arg.t()],
          targets: [target()]
        }
end
