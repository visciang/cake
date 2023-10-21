defmodule Dake.Dir do
  @spec include_ctx(Path.t()) :: Path.t()
  def include_ctx(base_dir) do
    Path.join(base_dir, ".dake/ctx")
  end

  @spec tmp :: Path.t()
  def tmp do
    Path.join(File.cwd!(), ".dake/tmp")
  end

  @spec output :: Path.t()
  def output do
    Path.join(File.cwd!(), ".dake/output")
  end

  @spec log :: Path.t()
  def log do
    Path.join(File.cwd!(), ".dake/log")
  end
end
