defmodule Cake do
  alias Cake.{Cli, Cmd, Dag, Dir, Parser, Preprocessor, Reference, Reporter, Validator}
  alias Cake.Parser.Cakefile

  @spec main([String.t()]) :: no_return()
  def main(cli_args) do
    setup_cake_dirs()

    Reporter.start_link()
    Reference.start_link()

    cmd_res =
      with {:ok, cmd} <- Cli.parse(cli_args) do
        cmd(cmd)
      end

    Reporter.stop(cmd_res)

    case cmd_res do
      :ok -> Cake.System.halt(:ok)
      {:ignore, reason} -> Cake.System.halt(:ok, reason)
      {:error, reason} -> Cake.System.halt(:error, reason)
      :timeout -> Cake.System.halt(:error, "timeout")
    end
  end

  @spec cmd(Cmd.t(), Path.t()) :: Cmd.result()
  def cmd(cmd, dir \\ ".") do
    cakefile_path = Path.join(dir, "Cakefile")

    with {:ok, cakefile} <- load_and_parse_cakefile(cakefile_path),
         {:preprocess, {:ok, cakefile}} <- {:preprocess, Preprocessor.expand(cakefile, args(cmd))},
         {:dag, {:ok, graph}} <- {:dag, Dag.extract(cakefile)},
         {:validator, :ok} <- {:validator, Validator.check(cakefile, graph)} do
      Cmd.exec(cmd, cakefile, graph)
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

  @spec setup_cake_dirs :: :ok
  defp setup_cake_dirs do
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
