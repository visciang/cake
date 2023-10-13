defmodule Dake.Reporter.Status do
  @type t :: :ok | :timeout | :log | {:error, reason :: term(), stacktrace :: nil | String.t()}

  defmacro ok do
    quote do: :ok
  end

  defmacro timeout do
    quote do: :timeout
  end

  defmacro log do
    quote do: :log
  end

  defmacro error(reason, stacktrace) do
    quote do
      {:error, unquote(reason), unquote(stacktrace)}
    end
  end
end
