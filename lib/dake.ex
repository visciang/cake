defmodule Dake do
  alias Dake.{Cli, Cmd, Dag, Parser, Preprocessor, Validator}
  alias Dake.Parser.Dakefile

  @spec main([String.t()]) :: no_return()
  def main(cli_args) do
    cmd =
      cli_args
      |> Cli.parse()
      |> exit_on_cli_args_error()

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
    |> exit_status()
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
  defp args(%Cli.Run{} = run) do
    Map.new(run.args)
  end

  defp args(_cmd), do: %{}

  @spec exit_status(Cmd.result()) :: no_return()
  defp exit_status(:ok), do: Dake.System.halt(:ok, "")
  defp exit_status({:error, reason}), do: Dake.System.halt(:error, "Pipeline failed: #{inspect(reason)}")

  @spec exit_on_dakefile_read_error({:ok, data} | {:error, File.posix()}, Path.t()) :: data when data: String.t()
  defp exit_on_dakefile_read_error({:ok, data}, _path), do: data

  defp exit_on_dakefile_read_error({:error, reason}, path) do
    Dake.System.halt(:error, "\nCannot open #{path}: (#{:file.format_error(reason)})")
  end

  @spec exit_on_cli_args_error(Cli.result()) :: Cmd.t()
  defp exit_on_cli_args_error({:ok, cmd}), do: cmd

  defp exit_on_cli_args_error({:error, reason}) do
    Dake.System.halt(:error, "\n#{reason}")
  end

  @spec exit_on_parse_error(Parser.result(), Path.t()) :: Dakefile.t()
  defp exit_on_parse_error({:ok, dakefile}, _path), do: dakefile

  defp exit_on_parse_error({:error, {content, line, column}}, path) do
    Dake.System.halt(:error, [
      "\nDakefile syntax error at #{path}:#{line}:#{column}\n",
      dakefile_error_context(content, line, column)
    ])
  end

  @spec exit_on_dag_error(Dag.result()) :: Dag.graph()
  defp exit_on_dag_error({:ok, graph}), do: graph

  defp exit_on_dag_error({:error, reason}) do
    Dake.System.halt(:error, ["\nTargets graph dependecy error:\n", inspect(reason)])
  end

  @spec exit_on_validation_error(Validator.result()) :: :ok
  defp exit_on_validation_error(:ok), do: :ok

  defp exit_on_validation_error({:error, reason}) do
    Dake.System.halt(:error, ["\nValidation error:\n", inspect(reason)])
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
