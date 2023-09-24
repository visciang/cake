defmodule Dake.CliArgs do
  @moduledoc """
  CLI argument parser
  """
  defmodule Ls do
    @moduledoc false
    defstruct [:tree]

    @type t :: %__MODULE__{
            tree: nil | boolean()
          }
  end

  defmodule Run do
    @moduledoc false
    @enforce_keys [:target, :args]
    defstruct @enforce_keys

    @type t :: %__MODULE__{
            target: String.t(),
            args: Keyword.t(String.t())
          }
  end

  @type arg :: Ls.t() | Run.t()
  @type result :: {:ok, arg()} | {:error, reason :: String.t()}

  @spec parse([String.t()]) :: result()
  def parse(args) do
    case args do
      ["ls" | args] ->
        {opts, []} = OptionParser.parse!(args, strict: [tree: :boolean])
        {:ok, struct!(Ls, opts)}

      ["run", target | target_args] ->
        case parse_target_args(target_args) do
          {:ok, target_args} ->
            {:ok, struct!(Run, target: target, args: target_args)}

          {:error, _reason} = error ->
            error
        end

      ["run"] ->
        {:error, "missing target"}

      _ ->
        {:error, "unknow command"}
    end
  rescue
    error in [OptionParser.ParseError] ->
      {:error, Exception.message(error)}
  end

  @spec parse_target_args([String.t()]) ::
          {:ok, [{name :: String.t(), value :: String.t()}]} | {:error, reason :: String.t()}
  defp parse_target_args(args) do
    Enum.reduce_while(args, {:ok, []}, fn
      "--" <> arg, {:ok, acc} ->
        case String.split(arg, "=", parts: 2) do
          [name, value] ->
            {:cont, {:ok, acc ++ [{name, value}]}}

          [bad_arg] ->
            {:halt, {:error, "bad target argument: #{bad_arg}"}}
        end

      bad_arg, {:ok, _acc} ->
        {:halt, {:error, "bad target argument: #{bad_arg}"}}
    end)
  end
end
