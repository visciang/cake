defmodule Dake.Parser.Target do
  defmodule Alias do
    @moduledoc """
    Target alias group `alias: <target>+`.
    """
    @enforce_keys [:target, :targets]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            target: String.t(),
            targets: [String.t(), ...]
          }
  end

  defmodule Docker do
    @moduledoc """
    Target docker:

    ```
    target:
        DAKE_OUTPUT output/
        FROM image
        RUN ...
    ```
    """
    @enforce_keys [:target, :commands]
    defstruct @enforce_keys

    @type command ::
            Dake.Parser.Docker.Arg.t()
            | Dake.Parser.Docker.From.t()
            | Dake.Parser.Docker.Command.t()
            | Dake.Parser.Docker.DakeOutput.t()
            | Dake.Parser.Docker.DakePush.t()

    @type t :: %__MODULE__{
            target: String.t(),
            commands: [command]
          }
  end
end
