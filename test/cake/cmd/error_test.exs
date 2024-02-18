defmodule Test.Cake.Cmd.Error do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  require Test.Support

  @moduletag :tmp_dir
  setup {Test.Support, :setup_cake_run}

  test "Cakefile no such file" do
    {result, output} =
      with_io(:stderr, fn ->
        Cake.main(["ls"])
      end)

    assert result == :error

    expected_output = """
    Cannot open ./Cakefile: (no such file or directory)
    """

    Test.Support.assert_output(output, expected_output)
  end

  test "Cakefile syntax error" do
    Test.Support.write_cakefile("""
    bad_syntax
    """)

    {result, output} =
      with_io(:stderr, fn ->
        Cake.main(["ls"])
      end)

    assert result == :error

    expected_output = """
    Cakefile syntax error at ./Cakefile:1:0

    bad_syntax
    ^
    """

    Test.Support.assert_output(output, expected_output)
  end
end
