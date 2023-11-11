defmodule Dake.Parser.Target do
  defmodule Alias do
    # Alias target group `alias: <target>+`

    @enforce_keys [:tgid, :tgids]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            tgid: Dake.Type.tgid(),
            tgids: [Dake.Type.tgid(), ...]
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
            Dake.Parser.Directive.Import.t()
            | Dake.Parser.Directive.Output.t()
            | Dake.Parser.Directive.Push.t()

    @type command ::
            Dake.Parser.Container.Arg.t()
            | Dake.Parser.Container.From.t()
            | Dake.Parser.Container.Command.t()

    @type t :: %__MODULE__{
            tgid: Dake.Type.tgid(),
            directives: [directive()],
            commands: [command()],
            included_from_ref: nil | String.t()
          }
  end
end
