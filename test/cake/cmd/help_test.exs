defmodule Test.Cake.Cmd.Help do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  require Test.Support

  @help """
  cake (Container-mAKE pipeline) 0.0.0

  USAGE:
      cake
      cake --version
      cake --help
      cake help subcommand

  SUBCOMMANDS:

      devshell        Development shell
      ls              List targets
      run             Run the pipeline

  """

  test "--version" do
    {result, output} =
      with_io(:stderr, fn ->
        Cake.main(["--version"])
      end)

    assert result == :ok
    assert output =~ "cake (Container-mAKE pipeline) 0.0.0"
  end

  test "--help" do
    {result, output} =
      with_io(:stderr, fn ->
        Cake.main(["--help"])
      end)

    assert result == :ok

    expected_output = @help

    Test.Support.assert_output(output, expected_output)
  end

  test "help subcommand" do
    {result, output} =
      with_io(:stderr, fn ->
        Cake.main(["help", "run"])
      end)

    assert result == :ok
    assert output =~ "Run the pipeline"
  end

  test "no args" do
    {result, output} =
      with_io(:stderr, fn ->
        Cake.main([])
      end)

    assert result == :ok

    expected_output = @help

    Test.Support.assert_output(output, expected_output)
  end
end
