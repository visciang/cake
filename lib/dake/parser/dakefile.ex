defmodule Dake.Parser.Dakefile do
  alias Dake.Parser.Directive

  defstruct includes: [], args: [], targets: []

  @type target :: Dake.Parser.Target.Docker.t() | Dake.Parser.Target.Alias.t()

  @type t :: %__MODULE__{
          includes: [Directive.Include.t()],
          args: [Dake.Parser.Docker.Arg.t()],
          targets: [target()]
        }
end
