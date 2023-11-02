defmodule Dake.Dir do
  @spec include_ctx(Path.t()) :: Path.t()
  def include_ctx(base_dir), do: Path.join(base_dir, ".dake/ctx")

  @spec git_ref :: Path.t()
  def git_ref, do: Path.join(File.cwd!(), ".dake/git")

  @spec tmp :: Path.t()
  def tmp, do: Path.join(File.cwd!(), ".dake/tmp")

  @spec output :: Path.t()
  def output, do: Path.join(File.cwd!(), ".dake/output")

  @spec log :: Path.t()
  def log, do: Path.join(File.cwd!(), ".dake/log")

  @spec local_include_ctx_dir(Path.t(), String.t()) :: Path.t()
  def local_include_ctx_dir(dakefile_path, include_path) do
    dakefile_dir = Path.dirname(dakefile_path)
    include_dir = Path.dirname(include_path)
    include_ctx_dir = include_ctx(dakefile_dir)
    Path.join(include_ctx_dir, include_dir)
  end
end
