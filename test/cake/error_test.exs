defmodule Test.Cake.Error do
  use ExUnit.Case, async: false

  import Mox
  require Test.Support

  @moduletag :tmp_dir
  setup {Test.Support, :setup_cake_run}

  test "bad command" do
    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg == ["unrecognized arguments: \"bad_command\""]
      :error
    end)

    result = Cake.main(["bad_command"])
    assert result == :error
  end

  test "bad sub command" do
    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error

      assert msg == [
               "invalid value \"bad\" for --progress option: supported progress value are [\"plain\", \"interactive\"]"
             ]

      :error
    end)

    result = Cake.main(["run", "--progress=bad"])
    assert result == :error
  end

  test "Cakefile no such file" do
    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg == "Cannot open Cakefile: (no such file or directory)"
      :error
    end)

    result = Cake.main(["ls"])
    assert result == :error
  end

  test "Cakefile syntax error" do
    Test.Support.write_cakefile("""
    bad_syntax
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg == "Cakefile syntax error at Cakefile:1:0\n\nbad_syntax\n^"
      :error
    end)

    result = Cake.main(["ls"])
    assert result == :error
  end
end
