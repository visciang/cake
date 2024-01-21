defmodule Test.Support do
  import ExUnit.Callbacks

  def setup_cake_run(%{tmp_dir: tmp_dir}) do
    cwd = File.cwd!()

    ansi_enabled = IO.ANSI.enabled?()
    Application.put_env(:elixir, :ansi_enabled, false)
    File.cd!(tmp_dir)

    on_exit(fn ->
      Application.put_env(:elixir, :ansi_enabled, ansi_enabled)
      File.cd!(cwd)
    end)
  end

  def normalize_output(output) do
    output
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> case do
      ["" | rest] -> rest
      res -> res
    end
  end

  def write_cakefile(content) do
    File.write!("Cakefile", content)
  end
end
