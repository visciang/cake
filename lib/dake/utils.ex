defmodule Dake.System do
  @dialyzer {:nowarn_function, halt: 1}

  @spec halt(:ok | :error, nil | IO.chardata()) :: no_return()
  def halt(exit_status, message \\ nil) do
    if message != nil, do: IO.puts(:stderr, message)

    case exit_status do
      :ok -> System.halt(0)
      :error -> System.halt(1)
    end
  end
end
