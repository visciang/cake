defmodule Cake.Dir do
  @spec include :: Path.t()
  def include, do: ".cake/include"

  @spec tmp :: Path.t()
  def tmp, do: ".cake/tmp"

  @spec output :: Path.t()
  def output, do: ".cake/output"

  @spec log :: Path.t()
  def log, do: ".cake/log"

  @spec execdir :: Path.t()
  def execdir, do: :persistent_term.get({:cake, :execdir})

  @spec set_execdir(dir :: Path.t()) :: :ok
  def set_execdir(dir), do: :persistent_term.put({:cake, :execdir}, dir)

  @spec setup_cake_dirs :: :ok
  def setup_cake_dirs do
    File.mkdir_p!(log())

    for dir <- [tmp(), output()] do
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

    :persistent_term.put({:cake, :cmd_wrapper_path}, path)

    File.write!(path, @cmd_wrapper)
    File.chmod!(path, 0o700)

    :ok
  end

  # coveralls-ignore-start

  @spec cmd_wrapper_path :: Path.t()
  def cmd_wrapper_path do
    :persistent_term.get({:cake, :cmd_wrapper_path})
  end

  # coveralls-ignore-stop
end
