defmodule Dake.Const do
  defmacro tmp_dir do
    quote do: ".dake/tmp"
  end

  defmacro output_dir do
    quote do: ".dake/output"
  end

  defmacro log_dir do
    quote do: ".dake/log"
  end
end
