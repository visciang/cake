defmodule Dake.Parser.Target do
  defmodule Alias do
    @moduledoc """
    Alias target group `alias: <target>+`.
    """

    alias Dake.Type

    @enforce_keys [:tgid, :tgids]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            tgid: Type.tgid(),
            tgids: [Type.tgid(), ...]
          }
  end

  defmodule Docker do
    @moduledoc """
    Docker target:

    ```
    @output output/
    target:
        FROM image
        ARG X=1
        RUN ...
    ```
    """

    alias Dake.Type

    @enforce_keys [:tgid, :commands]
    defstruct @enforce_keys ++ [directives: []]

    @type directive ::
            Dake.Parser.Docker.DakeOutput.t()
            | Dake.Parser.Docker.DakePush.t()
            | Dake.Parser.Docker.DakeImage.t()

    @type command ::
            Dake.Parser.Docker.Arg.t()
            | Dake.Parser.Docker.From.t()
            | Dake.Parser.Docker.Command.t()

    @type t :: %__MODULE__{
            tgid: Type.tgid(),
            directives: [directive()],
            commands: [command()]
          }
  end
end
