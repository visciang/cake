defmodule Cake.Pipeline.ContainerManager do
  alias Cake.Type

  @callback build(
              ns :: [Type.tgid()],
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

  @callback output([Type.tgid()], Type.tgid(), Type.pipeline_uuid(), [Path.t()], Path.t()) :: :ok

  @callback cleanup(Type.pipeline_uuid()) :: :ok

  @callback fq_image(Type.tgid(), Type.pipeline_uuid()) :: String.t()

  @callback fq_output_container(Type.tgid(), Type.pipeline_uuid()) :: String.t()
end
