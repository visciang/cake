defmodule Cake.Parser.Target.Local do
  # target: dep
  #     LOCAL /bin/sh
  #     ENV XXX=default_val
  #     echo "Hello ${XXX}"

  alias Cake.Parser.Directive.When
  alias Cake.Parser.Target.Container.Env
  alias Cake.Type

  @enforce_keys [:tgid, :interpreter, :script]
  defstruct @enforce_keys ++ [deps_tgids: [], directives: [], env: [], __included_from_ref: nil]

  @type directive :: When.t()

  @type t :: %__MODULE__{
          tgid: Type.tgid(),
          deps_tgids: [Type.tgid()],
          directives: [directive()],
          interpreter: String.t(),
          env: [Env.t()],
          script: String.t(),
          __included_from_ref: nil | Path.t()
        }
end
