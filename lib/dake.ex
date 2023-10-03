defmodule Dake do
  @moduledoc """
  Dake escript.
  """

  alias Dake.{CliArgs, Cmd, Dag, Parser, Preprocessor, Validator}
  alias Dake.Parser.Dakefile

  @spec main([String.t()]) :: :ok
  def main(cli_args) do
    dakefile_content =
      File.read("Dakefile")
      |> exit_on_dakefile_read_error()

    cmd =
      cli_args
      |> CliArgs.parse()
      |> exit_on_cli_args_error()

    dakefile =
      dakefile_content
      |> Parser.parse()
      |> exit_on_parse_error()

    args = args(dakefile, cmd)

    dakefile =
      dakefile
      |> Preprocessor.expand(args)
      |> exit_on_preprocessor_error()

    graph =
      dakefile
      |> Dag.extract()
      |> exit_on_dag_error()

    dakefile
    |> Validator.check(graph)
    |> exit_on_validation_error()

    Cmd.exec(cmd, dakefile, graph)

    :ok
  end

  @spec args(Dakefile.t(), Cmd.t()) :: Preprocessor.args()
  defp args(%Dakefile{} = dakefile, %CliArgs.Run{} = run) do
    args = Map.new(dakefile.args, &{&1.name, &1.default_value})
    run_args = Map.new(run.args)

    Map.merge(args, run_args)
  end

  defp args(_dakefile, _cmd), do: %{}

  @spec exit_on_dakefile_read_error({:ok, data} | {:error, File.posix()}) :: data when data: String.t()
  defp exit_on_dakefile_read_error({:ok, data}), do: data

  defp exit_on_dakefile_read_error({:error, reason}) do
    IO.puts(:stderr, "\nCannot open Dakefile: (#{:file.format_error(reason)})")
    System.halt(1)
  end

  @spec exit_on_cli_args_error(CliArgs.result()) :: Cmd.t()
  defp exit_on_cli_args_error({:ok, cmd}), do: cmd

  defp exit_on_cli_args_error({:error, reason}) do
    IO.puts(:stderr, "\n#{reason}")
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

  @spec exit_on_preprocessor_error(Preprocessor.result()) :: Dakefile.t()
  defp exit_on_preprocessor_error({:ok, %Dakefile{} = dakefile}), do: dakefile

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
