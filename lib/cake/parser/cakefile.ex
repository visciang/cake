defmodule Cake.Parser.Cakefile do
  alias Cake.Parser.{Alias, Container, Target}
  alias Cake.Parser.Directive.Include

  defstruct path: ".", includes: [], args: [], targets: []

  @type target :: Alias.t() | Target.t()

  @type t :: %__MODULE__{
          path: Path.t(),
          includes: [Include.t()],
          args: [Container.Arg.t()],
          targets: [target()]
        }
end
