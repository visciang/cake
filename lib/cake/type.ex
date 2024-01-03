defmodule Cake.Type do
  @type tgid :: String.t()
  @type pipeline_uuid :: String.t()
  @type progress :: :plain | :interactive
end
