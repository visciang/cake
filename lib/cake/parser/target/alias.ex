defmodule Cake.Parser.Target.Alias do
  # Alias target group `alias: <target>*`

  alias Cake.Type

  @enforce_keys [:tgid]
  defstruct @enforce_keys ++ [deps_tgids: [], __included_from_ref: nil]

  @type t :: %__MODULE__{
          tgid: Type.tgid(),
          deps_tgids: [Type.tgid()],
          __included_from_ref: nil | Path.t()
        }
end
