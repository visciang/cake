defmodule Test.Cake.Include do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Mox
  require Test.Support

  @moduletag :tmp_dir
  setup {Test.Support, :setup_cake_run}

  test "included Cakefile does not exists" do
    File.mkdir_p!("./dir")

    Test.Support.write_cakefile("""
    @include ./dir
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg == "Preprocessing error:\n\"Cannot find Cakefile in include from ./dir\""
      :ok
    end)

    {result, _output} =
      with_io(fn ->
        Cake.main(["ls"])
      end)

    assert result == :ok
  end

  test "included Cakefile from non existing local directory" do
    Test.Support.write_cakefile("""
    @include ./dir
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg == "Preprocessing error:\n\"@include ./dir failed: directory not found\""
      :ok
    end)

    {result, _output} =
      with_io(fn ->
        Cake.main(["ls"])
      end)

    assert result == :ok
  end

  test "included Cakefile from local directory" do
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

           Targets:
             all: inc_target_1 inc_target_2
             inc_target_1:
             inc_target_2:
             target:
           """
  end

  test "included Cakefile outside the current project workdir" do
    Test.Support.write_cakefile("dir", """
    ARG inc_arg

    all: inc_target_1 inc_target_2

    inc_target_1:
        FROM scratch

    inc_target_2:
        FROM scratch
    """)

    Test.Support.write_cakefile("project_dir", """
    ARG arg

    @include ../dir

    target:
        FROM scratch
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert msg == nil
      assert exit_status == :ok
      :ok
    end)

    {result, output} =
      with_io(fn ->
        Cake.main(["ls", "--workdir", "project_dir"])
      end)

    assert result == :ok

    assert output =~ """
           Global arguments:
             arg
             inc_arg

           Targets:
             all: inc_target_1 inc_target_2
             inc_target_1:
             inc_target_2:
             target:
           """
  end

  test "included Cakefile outside the current exec dir" do
    Test.Support.write_cakefile("dir", """
    ARG inc_arg

    all: inc_target_1 inc_target_2

    inc_target_1:
        FROM scratch

    inc_target_2:
        FROM scratch
    """)

    Test.Support.write_cakefile("project_dir", """
    ARG arg

    @include ../dir

    target:
        FROM scratch
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert msg ==
               "Preprocessing error:\n\"@include ../dir failed: '../dir' is not a sub-directory of the cake execution directory\""

      assert exit_status == :error
      :ok
    end)

    {result, _output} =
      with_io(fn ->
        File.cd!("project_dir", fn ->
          Cake.main(["ls"])
        end)
      end)

    assert result == :ok
  end
end
