defmodule Cake.Parser.Cakefile do
  alias Cake.Parser.Directive.Include
  alias Cake.Parser.Target.{Alias, Container}

  defstruct path: ".", includes: [], args: [], targets: []

  @type target :: Alias.t() | Container.t()

  @type t :: %__MODULE__{
          path: Path.t(),
          includes: [Include.t()],
          args: [Container.Arg.t()],
          targets: [target()]
        }
end
