defmodule Cake.Dir do
  @spec include_ctx(Path.t()) :: Path.t()
  def include_ctx(base_dir), do: Path.join(base_dir, ".cake/ctx")

  @spec git_ref :: Path.t()
  def git_ref, do: Path.join(File.cwd!(), ".cake/git")

  @spec tmp :: Path.t()
  def tmp, do: Path.join(File.cwd!(), ".cake/tmp")

  @spec output :: Path.t()
  def output, do: Path.join(File.cwd!(), ".cake/output")

  @spec log :: Path.t()
  def log, do: Path.join(File.cwd!(), ".cake/log")

  @spec local_include_ctx_dir(Path.t(), String.t()) :: Path.t()
  def local_include_ctx_dir(cakefile_path, include_path) do
    cakefile_dir = Path.dirname(cakefile_path)
    include_dir = Path.dirname(include_path)
    include_ctx_dir = include_ctx(cakefile_dir)
    Path.join(include_ctx_dir, include_dir)
  end

  @spec setup_cake_dirs :: :ok
  def setup_cake_dirs do
    File.mkdir_p!(log())

    for dir <- [tmp(), output(), include_ctx(File.cwd!())] do
      File.rm_rf!(dir)
      File.mkdir_p!(dir)
    end

    :ok
  end

  # Ref: https://hexdocs.pm/elixir/Port.html#module-zombie-operating-system-processes
  @cmd_wrapper """
  #!/usr/bin/env bash

  # Start the program in the background
  exec "$@" &
  pid1=$!

  # Silence warnings from here on
  exec >/dev/null 2>&1

  # Read from stdin in the background and
  # kill running program when stdin closes
  exec 0<&0 $(
    while read; do :; done
    kill -KILL $pid1
  ) &
  pid2=$!

  # Clean up
  wait $pid1
  ret=$?
  kill -KILL $pid2
  exit $ret
  """

  @spec install_cmd_wrapper_script :: :ok
  def install_cmd_wrapper_script do
    path = Path.join(System.tmp_dir!(), "cmd_wrapper.sh")

    :persistent_term.put(:cake_cmd_wrapper_path, path)

    File.write!(path, @cmd_wrapper)
    File.chmod!(path, 0o700)

    :ok
  end

  # coveralls-ignore-start

  @spec cmd_wrapper_path :: Path.t()
  def cmd_wrapper_path do
    :persistent_term.get(:cake_cmd_wrapper_path)
  end

  # coveralls-ignore-stop
end
