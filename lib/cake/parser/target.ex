defmodule Cake.Parser.Target do
  # target:
  #     @output output/
  #     FROM image
  #     ARG X=1
  #     RUN ...

  alias Cake.Parser.Container.{Arg, Command, From}
  alias Cake.Parser.Directive.{Import, Output, Push}
  alias Cake.Type

  @enforce_keys [:tgid]
  defstruct @enforce_keys ++ [included_from_ref: nil, directives: [], commands: []]

  @type directive :: Import.t() | Output.t() | Push.t()
  @type command :: Arg.t() | From.t() | Command.t()

  @type t :: %__MODULE__{
          tgid: Type.tgid(),
          directives: [directive()],
          commands: [command()],
          included_from_ref: nil | String.t()
        }
end
