defmodule Cake do
  alias Cake.{Cli, Cmd, Dag, Dir, Parser, Preprocessor, Reference, Validator}
  alias Cake.Parser.Cakefile

  @spec main([String.t()]) :: no_return()
  def main(cli_args) do
    Reference.start_link()
    Dir.install_cmd_wrapper_script()

    res =
      with {:ok, cmd} <- Cli.parse(cli_args) do
        cmd(cmd)
      end

    case res do
      :ok -> Cake.System.halt(:ok)
      :timeout -> Cake.System.halt(:error, "timeout")
      {:ignore, reason} -> Cake.System.halt(:ok, reason)
      {:error, reason} -> Cake.System.halt(:error, reason)
    end
  end

  @spec cmd(Cmd.t(), Path.t()) :: Cmd.result()
  def cmd(cmd, dir \\ ".") do
    cakefile_path = Path.join(dir, "Cakefile")

    with {:parse, {:ok, cakefile}} <- {:parse, load_and_parse_cakefile(cakefile_path)},
         {:preprocess, {:ok, cakefile}} <- {:preprocess, Preprocessor.expand(cakefile, args(cmd))},
         {:dag, {:ok, graph}} <- {:dag, Dag.extract(cakefile)},
         {:validator, :ok} <- {:validator, Validator.check(cakefile, graph)} do
      Cmd.exec(cmd, cakefile, graph)
    else
      {:parse, {:error, _} = error} ->
        error

      {:preprocess, {:error, reason}} ->
        {:error, "Preprocessing error:\n#{inspect(reason)}"}

      {:dag, {:error, reason}} ->
        {:error, "Targets graph dependency error:\n#{inspect(reason)}"}

      {:validator, {:error, reason}} ->
        {:error, "Validation error:\n#{inspect(reason)}"}
    end
  end

  @spec load_and_parse_cakefile(Path.t()) :: {:ok, Cakefile.t()} | {:error, reason :: String.t()}
  def load_and_parse_cakefile(path) do
    with {:read, {:ok, file}} <- {:read, File.read(path)},
         {:parse, {:ok, cakefile}} <- {:parse, Parser.parse(file, path)} do
      {:ok, cakefile}
    else
      {:read, {:error, reason}} ->
        {:error, "Cannot open #{path}: (#{:file.format_error(reason)})"}

      {:parse, {:error, {content, line, column}}} ->
        ctx_msg = cakefile_error_context(content, line, column)
        {:error, "Cakefile syntax error at #{path}:#{line}:#{column}\n#{ctx_msg}"}
    end
  end

  @spec args(Cmd.t()) :: Preprocessor.args()
  defp args(cmd) do
    case cmd do
      %Cli.Run{} -> Map.new(cmd.args)
      _ -> %{}
    end
  end

  @spec cakefile_error_context(String.t(), pos_integer(), pos_integer()) :: String.t()
  defp cakefile_error_context(cakefile_content, line, column) do
    error_line =
      cakefile_content
      |> String.split("\n")
      |> Enum.at(line - 1)

    error_column_pointer = String.duplicate(" ", column) <> "^"
    "\n#{error_line}\n#{error_column_pointer}"
  end
end
