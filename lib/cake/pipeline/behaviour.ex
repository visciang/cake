defmodule Cake.Pipeline.Behaviour do
  alias Cake.Type

  defmodule Local do
    alias Cake.Parser.Target.Local

    @callback run(Local.t(), env :: %{(name :: String.t()) => value :: String.t()}, Type.pipeline_uuid()) :: :ok
  end

  defmodule Container do
    @callback build(
                Type.tgid(),
                tags :: [String.t()],
                build_args :: [{name :: String.t(), value :: String.t()}],
                containerfile :: Path.t(),
                no_cache :: boolean(),
                secrets :: [String.t()],
                build_ctx :: Path.t(),
                Type.pipeline_uuid()
              ) :: :ok

    @callback shell(Type.tgid(), Type.pipeline_uuid(), devshell? :: boolean()) :: :ok
    @callback output(Type.tgid(), Type.pipeline_uuid(), [Path.t()], Path.t()) :: :ok
    @callback cleanup(Type.pipeline_uuid()) :: :ok
    @callback fq_image(Type.tgid(), Type.pipeline_uuid()) :: String.t()
    @callback fq_output_container(Type.tgid(), Type.pipeline_uuid()) :: String.t()
  end
end
