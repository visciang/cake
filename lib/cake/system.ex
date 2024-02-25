defmodule Cake.System do
  @spec halt(:ok | :error, nil | String.t() | term()) :: no_return()
  def halt(exit_status, message \\ nil) do
    system = Application.get_env(:cake, :system_behaviour, Cake.SystemImpl)
    system.halt(exit_status, message)
  end
end

defmodule Cake.SystemBehaviour do
  @callback halt(:ok | :error, nil | String.t() | term()) :: no_return()
end

# coveralls-ignore-start

defmodule Cake.SystemImpl do
  @dialyzer {:nowarn_function, halt: 2}

  @behaviour Cake.SystemBehaviour

  @impl true
  def halt(exit_status, message) do
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

# coveralls-ignore-stop
