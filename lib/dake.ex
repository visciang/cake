defmodule Dake do
  alias Dake.{Cli, Cmd, Dag, Dir, Parser, Preprocessor, Reference, Reporter, Validator}
  alias Dake.Parser.Dakefile

  @spec main([String.t()]) :: no_return()
  def main(cli_args) do
    setup_dake_dirs()

    Reporter.start_link()
    Reference.start_link()

    cmd_res =
      with {:ok, cmd} <- Cli.parse(cli_args) do
        cmd(cmd)
      end

    Reporter.stop(cmd_res)

    case cmd_res do
      :ok -> Dake.System.halt(:ok)
      {:ignore, reason} -> Dake.System.halt(:ok, reason)
      {:error, reason} -> Dake.System.halt(:error, reason)
      :timeout -> Dake.System.halt(:error, "timeout")
    end
  end

  @spec cmd(Cmd.t(), Path.t()) :: Cmd.result()
  def cmd(cmd, dir \\ ".") do
    dakefile_path = Path.join(dir, "Dakefile")

    with {:ok, dakefile} <- load_and_parse_dakefile(dakefile_path),
         {:preprocess, {:ok, dakefile}} <- {:preprocess, Preprocessor.expand(dakefile, args(cmd))},
         {:dag, {:ok, graph}} <- {:dag, Dag.extract(dakefile)},
         {:validator, :ok} <- {:validator, Validator.check(dakefile, graph)} do
      Cmd.exec(cmd, dakefile, graph)
    else
      {:error, _} = error ->
        error

      {:preprocess, {:error, reason}} ->
        {:error, "Preprocessing error:\n#{inspect(reason)}"}

      {:dag, {:error, reason}} ->
        {:error, "Targets graph dependency error:\n#{inspect(reason)}"}

      {:validator, {:error, reason}} ->
        {:error, "Validation error:\n#{inspect(reason)}"}
    end
  end

  @spec load_and_parse_dakefile(Path.t()) :: {:ok, Dakefile.t()} | {:error, reason :: String.t()}
  def load_and_parse_dakefile(path) do
    with {:read, {:ok, file}} <- {:read, File.read(path)},
         {:parse, {:ok, dakefile}} <- {:parse, Parser.parse(file, path)} do
      {:ok, dakefile}
    else
      {:read, {:error, reason}} ->
        {:error, "Cannot open #{path}: (#{:file.format_error(reason)})"}

      {:parse, {:error, {content, line, column}}} ->
        ctx_msg = dakefile_error_context(content, line, column)
        {:error, "Dakefile syntax error at #{path}:#{line}:#{column}\n#{ctx_msg}"}
    end
  end

  @spec setup_dake_dirs :: :ok
  defp setup_dake_dirs do
    File.mkdir_p!(Dir.log())

    [Dir.tmp(), Dir.output(), Dir.include_ctx(File.cwd!())]
    |> Enum.each(fn dir ->
      File.rm_rf!(dir)
      File.mkdir_p!(dir)
    end)
  end

  @spec args(Cmd.t()) :: Preprocessor.args()
  defp args(%Cli.Run{} = run) do
    Map.new(run.args)
  end

  defp args(_cmd), do: %{}

  @spec dakefile_error_context(String.t(), pos_integer(), pos_integer()) :: String.t()
  defp dakefile_error_context(dakefile_content, line, column) do
    error_line =
      dakefile_content
      |> String.split("\n")
      |> Enum.at(line - 1)

    error_column_pointer = String.duplicate(" ", column) <> "^"
    "\n#{error_line}\n#{error_column_pointer}"
  end
end
