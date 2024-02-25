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

  test "included Cakefile from local path" do
    Test.Support.write_cakefile("dir", """
    ARG inc_arg

    all: inc_target_1 inc_target_2

    inc_target_1:
        FROM scratch

    inc_target_2:
        FROM scratch
    """)

    Test.Support.write_cakefile("""
    ARG arg

    @include ./dir

    target:
        FROM scratch
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
             arg
             inc_arg

           Aliases:
             all: inc_target_1 inc_target_2

           Targets:
             inc_target_1:
             inc_target_2:
             target:
           """
  end
end
