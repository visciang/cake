defmodule Test.Cake.Cmd.Help do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

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

        run        Run the pipeline
        ls         List targets

    """

    expected_output = Test.Support.normalize_output(expected_output)
    output = Test.Support.normalize_output(output)
    assert output == expected_output
  end
end
