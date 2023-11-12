defmodule Cake.Reporter.Status do
  @type t :: :ok | :timeout | {:error, reason :: term(), stacktrace :: nil | String.t()}

  defmacro ok do
    quote do: :ok
  end

  defmacro timeout do
    quote do: :timeout
  end

  defmacro error(reason, stacktrace) do
    quote do
      {:error, unquote(reason), unquote(stacktrace)}
    end
  end
end
