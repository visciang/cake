defmodule Test.Cake.Cmd.Ls do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  setup {Test.Support, :setup_cake_run}

  test "missing Cakefile" do
    {result, output} =
      with_io(:stderr, fn ->
        Cake.main(["ls"])
      end)

    assert result == :error

    expected_output = """
    Cannot open ./Cakefile: (no such file or directory)
    """

    expected_output = Test.Support.normalize_output(expected_output)
    output = Test.Support.normalize_output(output)
    assert output == expected_output
  end

  test "list targets" do
    Test.Support.write_cakefile("""
    ARG global_arg_1=default

    target_1:
        @output output
        FROM scratch

    target_2:
        @devshell
        FROM scratch
        ARG target_arg_1
        ARG target_arg_2="default"
    """)

    {result, output} =
      with_io(:stdio, fn ->
        Cake.main(["ls"])
      end)

    assert result == :ok

    expected_output = """
    Global arguments:
      global_arg_1="default"

    Targets:
      target_1:
        @output output
      target_2:
        @devshell
        target_arg_1
        target_arg_2="default"
    """

    expected_output = Test.Support.normalize_output(expected_output)
    output = Test.Support.normalize_output(output)
    assert output == expected_output
  end
end
