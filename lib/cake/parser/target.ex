defmodule Cake.Parser.Target do
  defmodule Alias do
    # Alias target group `alias: <target>+`

    @enforce_keys [:tgid, :tgids]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            tgid: Cake.Type.tgid(),
            tgids: [Cake.Type.tgid(), ...]
          }
  end

  defmodule Container do
    # target:
    #     @output output/
    #     FROM image
    #     ARG X=1
    #     RUN ...

    @enforce_keys [:tgid, :commands]
    defstruct @enforce_keys ++ [included_from_ref: nil, directives: []]

    @type directive ::
            Cake.Parser.Directive.Import.t()
            | Cake.Parser.Directive.Output.t()
            | Cake.Parser.Directive.Push.t()

    @type command ::
            Cake.Parser.Container.Arg.t()
            | Cake.Parser.Container.From.t()
            | Cake.Parser.Container.Command.t()

    @type t :: %__MODULE__{
            tgid: Cake.Type.tgid(),
            directives: [directive()],
            commands: [command()],
            included_from_ref: nil | String.t()
          }
  end
end
