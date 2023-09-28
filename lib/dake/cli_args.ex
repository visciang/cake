defmodule Dake.CliArgs do
  @moduledoc """
  CLI argument parser
  """

  alias Dake.Type

  defmodule Ls do
    @moduledoc false
    defstruct [:tree]

    @type t :: %__MODULE__{
            tree: nil | boolean()
          }
  end

  defmodule Run do
    @moduledoc false
    @enforce_keys [:tgid, :args, :push]
    defstruct @enforce_keys

    @type arg :: {name :: String.t(), value :: String.t()}
    @type t :: %__MODULE__{
            tgid: Type.tgid(),
            args: [arg()],
            push: boolean()
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

      ["run" | run_args] ->
        with {run_options, [tgid | target_args]} <- OptionParser.parse_head!(run_args, switches: [push: :boolean]),
             {:ok, target_args} <- parse_target_args(target_args) do
          push = run_options[:push] || false
          {:ok, struct!(Run, tgid: tgid, args: target_args, push: push)}
        else
          {_, _} ->
            {:error, "missing target"}

          {:error, _reason} = error ->
            error
        end

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
