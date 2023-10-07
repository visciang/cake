defmodule Dake do
  @moduledoc """
  Dake escript.
  """

  alias Dake.{CliArgs, Cmd, Dag, Parser, Preprocessor, Validator}
  alias Dake.Parser.Dakefile

  @spec main([String.t()]) :: :ok
  def main(cli_args) do
    cmd =
      cli_args
      |> CliArgs.parse()
      |> exit_on_cli_args_error()

    File.rm_rf!(".dake")
    File.mkdir!(".dake")

    dakefile = load_and_parse_dakefile("Dakefile")
    dakefile = Preprocessor.expand(dakefile, args(cmd))

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

  @spec load_and_parse_dakefile(Path.t()) :: Dakefile.t()
  def load_and_parse_dakefile(path) do
    path
    |> File.read()
    |> exit_on_dakefile_read_error(path)
    |> Parser.parse()
    |> exit_on_parse_error(path)
  end

  @spec args(Cmd.t()) :: Preprocessor.args()
  defp args(%CliArgs.Run{} = run) do
    Map.new(run.args)
  end

  defp args(_cmd), do: %{}

  @spec exit_on_dakefile_read_error({:ok, data} | {:error, File.posix()}, Path.t()) :: data when data: String.t()
  defp exit_on_dakefile_read_error({:ok, data}, _path), do: data

  defp exit_on_dakefile_read_error({:error, reason}, path) do
    IO.puts(:stderr, "\nCannot open #{path}: (#{:file.format_error(reason)})")
    System.halt(1)
  end

  @spec exit_on_cli_args_error(CliArgs.result()) :: Cmd.t()
  defp exit_on_cli_args_error({:ok, cmd}), do: cmd

  defp exit_on_cli_args_error({:error, reason}) do
    IO.puts(:stderr, "\n#{reason}")
    System.halt(1)
  end

  @spec exit_on_parse_error(Parser.result(), Path.t()) :: Dakefile.t()
  defp exit_on_parse_error({:ok, dakefile}, _path), do: dakefile

  defp exit_on_parse_error({:error, {content, line, column}}, path) do
    IO.puts(:stderr, "\nDakefile syntax error at #{path}:#{line}:#{column}")
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
