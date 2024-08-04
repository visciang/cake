# coveralls-ignore-start

defmodule Cake.Reporter.Status do
  @type t :: :ok | :timeout | :ignore | {:error, reason :: term(), stacktrace :: nil | String.t()}

  defmacro ok do
    quote do: :ok
  end

  defmacro timeout do
    quote do: :timeout
  end

  defmacro ignore do
    quote do: :ignore
  end

  defmacro error(reason, stacktrace) do
    quote do: {:error, unquote(reason), unquote(stacktrace)}
  end
end

# coveralls-ignore-stop
