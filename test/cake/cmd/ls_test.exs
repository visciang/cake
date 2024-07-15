defmodule Test.Cake.Cmd.Ls do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Mox
  require Test.Support

  @moduletag :tmp_dir
  setup {Test.Support, :setup_cake_run}

  test "basic" do
    Test.Support.write_cakefile("""
    ARG global_arg_1=default

    all: target_1 target_2

    target_1:
        @output output
        FROM scratch

    target_2:
        @devshell
        FROM scratch
        ARG target_arg_1
        ARG target_arg_2="default"
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :ok
      assert msg == nil
      :ok
    end)

    {result, output} =
      with_io(fn ->
        Cake.main(["ls"])
      end)

    assert result == :ok

    assert output =~ """
           Global arguments:
             global_arg_1="default"

           Aliases:
             all: target_1 target_2

           Targets:
             target_1:
               @output output
             target_2:
               @devshell
               target_arg_1
               target_arg_2="default"
           """
  end
end
