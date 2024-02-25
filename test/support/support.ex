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

  def write_cakefile(dir \\ ".", content) do
    File.mkdir_p!(dir)
    cakekfile_path = Path.join(dir, "Cakefile")
    File.write!(cakekfile_path, content)
  end
end
