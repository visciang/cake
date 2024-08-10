defmodule Cake.System do
  @spec find_executable(program :: String.t()) :: String.t() | nil
  def find_executable(program) do
    system = Application.get_env(:cake, :system_behaviour, Cake.SystemImpl)
    system.find_executable(program)
  end

  @spec cmd(String.t(), [String.t()], keyword()) :: {Collectable.t(), exit_status :: non_neg_integer()}
  def cmd(cmd, args, opts \\ []) do
    system = Application.get_env(:cake, :system_behaviour, Cake.SystemImpl)
    system.cmd(cmd, args, opts)
  end

  @spec halt(:ok | :error, nil | String.t() | term()) :: no_return()
  def halt(exit_status, message \\ nil) do
    system = Application.get_env(:cake, :system_behaviour, Cake.SystemImpl)
    system.halt(exit_status, message)
  end
end

defmodule Cake.SystemBehaviour do
  @callback find_executable(program :: String.t()) :: String.t() | nil
  @callback cmd(String.t(), [String.t()], keyword()) :: {Collectable.t(), exit_status :: non_neg_integer()}
  @callback halt(:ok | :error, nil | String.t() | term()) :: no_return()
end

# coveralls-ignore-start

defmodule Cake.SystemImpl do
  @dialyzer {:nowarn_function, halt: 2}

  @behaviour Cake.SystemBehaviour

  @impl true
  def find_executable(program) do
    System.find_executable(program)
  end

  @impl true
  def cmd(cmd, args, opts) do
    System.cmd(cmd, args, opts)
  end

  @impl true
  def halt(exit_status, message) do
    if message != nil do
      message = if is_binary(message), do: message, else: inspect(message, pretty: true)
      IO.puts(:stderr, "\n#{message}")
    end

    case exit_status do
      :ok -> System.halt(0)
      :error -> System.halt(1)
    end
  end
end

# coveralls-ignore-stop
