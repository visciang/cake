defmodule Test.Cake.Cmd.Help do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  require Test.Support

  test "no args" do
    {result, output} =
      with_io(:stderr, fn ->
        Cake.main([])
      end)

    assert result == :ok

    expected_output = """
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

    Test.Support.assert_output(output, expected_output)
  end
end
