defmodule Dake.System do
  @spec halt(:ok | :error, IO.chardata()) :: no_return()
  def halt(exit_status, message) do
    case exit_status do
      :ok ->
        IO.puts(:stdio, message)
        System.halt(0)

      :error ->
        IO.puts(:stderr, message)
        System.halt(1)
    end
  end
end
