defmodule Test.Cake.Validator do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  @moduletag :tmp_dir

  setup {Test.Support, :setup_cake_run}

  test "alias targets cannot be referenced in FROM/COPY instructions" do
    Test.Support.write_cakefile("""
    ARG global_arg_1=default

    alias_target: target_1

    target_1:
        FROM scratch

    target_2:
        FROM +alias_target
        COPY --from=alias_target xxx
    """)

    {result, output} =
      with_io(:stderr, fn ->
        Cake.main(["ls"])
      end)

    expected_output = """
    Validation error:
    "alias targets [\\"alias_target\\"] cannot be referenced in FROM/COPY instructions"
    """

    expected_output = Test.Support.normalize_output(expected_output)
    output = Test.Support.normalize_output(output)

    assert result == :error
    assert output == expected_output
  end

  test "FROM AS not allowed" do
    Test.Support.write_cakefile("""
    target_1:
        FROM scratch AS xxx
    """)

    {result, output} =
      with_io(:stderr, fn ->
        Cake.main(["ls"])
      end)

    expected_output = """
    Validation error:
    "'FROM .. AS ..' form is not allowed, please remove the AS argument under target_1"
    """

    expected_output = Test.Support.normalize_output(expected_output)
    output = Test.Support.normalize_output(output)

    assert result == :error
    assert output == expected_output
  end

  test "target should start with a FROM" do
    Test.Support.write_cakefile("""
    target:
        RUN cmd
    """)

    {result, output} =
      with_io(:stderr, fn ->
        Cake.main(["ls"])
      end)

    expected_output = """
    Validation error:
    "target doesn't start with a FROM command"
    """

    expected_output = Test.Support.normalize_output(expected_output)
    output = Test.Support.normalize_output(output)

    assert result == :error
    assert output == expected_output
  end

  test "@push target can only be terminal target" do
    Test.Support.write_cakefile("""
    target_1:
        @push
        FROM scratch

    target_2:
        FROM +target_1
    """)

    {result, output} =
      with_io(:stderr, fn ->
        Cake.main(["ls"])
      end)

    expected_output = """
    Validation error:
    "push targets [\\"target_1\\"] can be only terminal target"
    """

    expected_output = Test.Support.normalize_output(expected_output)
    output = Test.Support.normalize_output(output)

    assert result == :error
    assert output == expected_output
  end
end
