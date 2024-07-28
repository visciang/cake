defmodule Cake.Parser.Cakefile do
  alias Cake.Parser.Directive.Include
  alias Cake.Parser.Target.{Alias, Container, Local}

  defstruct path: ".", includes: [], args: [], targets: []

  @type target :: Alias.t() | Container.t() | Local.t()

  @type t :: %__MODULE__{
          path: Path.t(),
          includes: [Include.t()],
          args: [Container.Arg.t()],
          targets: [target()]
        }
end
