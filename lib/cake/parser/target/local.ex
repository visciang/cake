defmodule Cake.Parser.Target.Local do
  # target: dep
  #     LOCAL /bin/sh -c
  #     ENV XXX=default_val
  #     echo "Hello ${XXX}"

  alias Cake.Parser.Target.Container.Env
  alias Cake.Type

  @enforce_keys [:tgid, :interpreter, :script]
  defstruct @enforce_keys ++ [deps_tgids: [], env: [], included_from_ref: nil]

  @type t :: %__MODULE__{
          tgid: Type.tgid(),
          deps_tgids: [Type.tgid()],
          included_from_ref: nil | Path.t(),
          interpreter: String.t(),
          env: [Env.t()],
          script: String.t()
        }
end
