defmodule Dake do
  @moduledoc """
  Dake escript.
  """

  alias Dake.CliArgs
  alias Dake.Cmd
  alias Dake.Dag
  alias Dake.Parser
  alias Dake.Parser.Dakefile
  alias Dake.Validator

  @spec main([String.t()]) :: :ok
  def main(args) do
    args =
      args
      |> CliArgs.parse()
      |> exit_on_cli_args_error()

    dakefile_content = read_dakefile()

    dakefile =
      dakefile_content
      |> Parser.parse()
      |> exit_on_parse_error()

    graph =
      dakefile
      |> Dag.extract()
      |> exit_on_dag_error()

    Validator.check(dakefile, graph)
    |> exit_on_validation_error()

    Cmd.exec(args, dakefile, graph)

    :ok
  end

  @spec read_dakefile :: String.t()
  defp read_dakefile do
    case File.read("Dakefile") do
      {:ok, data} ->
        data

      {:error, _} ->
        IO.puts(:stderr, "\nCannot read Dakefile")
        System.halt(1)
    end
  end

  @spec exit_on_cli_args_error(CliArgs.result()) :: CliArgs.arg()
  defp exit_on_cli_args_error({:ok, arg}), do: arg

  defp exit_on_cli_args_error({:error, reason}) do
    IO.puts(:stderr, "\nargument error:\n#{reason}")
    System.halt(1)
  end

  @spec exit_on_parse_error(Parser.result()) :: Dakefile.t()
  defp exit_on_parse_error({:ok, dakefile}), do: dakefile

  defp exit_on_parse_error({:error, {content, line, column}}) do
    IO.puts(:stderr, "\nDakefile syntax error at #{line}:#{column}")
    IO.puts(:stderr, dakefile_error_context(content, line, column))
    System.halt(1)
  end

  @spec exit_on_dag_error(Dag.result()) :: Dag.graph()
  defp exit_on_dag_error({:ok, graph}), do: graph

  defp exit_on_dag_error({:error, reason}) do
    IO.puts(:stderr, "\nTargets graph dependecy error:")
    IO.puts(:stderr, inspect(reason))
    System.halt(1)
  end

  @spec exit_on_validation_error(Validator.result()) :: :ok
  defp exit_on_validation_error(:ok), do: :ok

  defp exit_on_validation_error({:error, reason}) do
    IO.puts(:stderr, "\nValidation error:")
    IO.puts(:stderr, inspect(reason))
    System.halt(1)
  end

  @spec dakefile_error_context(String.t(), pos_integer(), pos_integer()) :: String.t()
  defp dakefile_error_context(dakefile_content, line, column) do
    error_line =
      dakefile_content
      |> String.split("\n")
      |> Enum.at(line - 1)

    error_column_pointer = String.duplicate(" ", column) <> "^"
    "\n" <> error_line <> "\n" <> error_column_pointer
  end
end
