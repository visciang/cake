defmodule Dake.Const do
  defmacro dake_dir do
    quote do: ".dake"
  end

  defmacro dake_output_dir do
    quote do: ".dake_output"
  end
end
