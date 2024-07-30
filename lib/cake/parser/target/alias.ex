defmodule Cake.Parser.Target.Alias do
  # Alias target group `alias: <target>*`

  alias Cake.Type

  @enforce_keys [:tgid]
  defstruct @enforce_keys ++ [deps_tgids: []]

  @type t :: %__MODULE__{
          tgid: Type.tgid(),
          deps_tgids: [Type.tgid()]
        }
end
