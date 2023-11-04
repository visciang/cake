defmodule Dake.System do
  @dialyzer {:nowarn_function, halt: 1}

  @spec halt(:ok | :error, nil | String.t() | term()) :: no_return()
  def halt(exit_status, message \\ nil) do
    if message != nil do
      message = if is_binary(message), do: message, else: inspect(message)
      IO.puts(:stderr, "\n#{message}")
    end

    case exit_status do
      :ok -> System.halt(0)
      :error -> System.halt(1)
    end
  end
end