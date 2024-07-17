defmodule Cake.Parser.Target.Alias do
  # Alias target group `alias: <target>+`

  alias Cake.Type

  @enforce_keys [:tgid, :tgids]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          tgid: Type.tgid(),
          tgids: [Type.tgid(), ...]
        }
end
