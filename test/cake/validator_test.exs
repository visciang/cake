defmodule Test.Cake.Validator do
  use ExUnit.Case, async: false

  import Mox

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

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg =~ "Validation error:"
      assert msg =~ "alias targets [\\\"alias_target\\\"] cannot be referenced in FROM/COPY instructions"
      :error
    end)

    result = Cake.main(["ls"])
    assert result == :error
  end

  test "FROM AS not allowed" do
    Test.Support.write_cakefile("""
    target_1:
        FROM scratch AS xxx
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg =~ "Validation error:"
      assert msg =~ "'FROM .. AS ..' form is not allowed, please remove the AS argument under target_1"
      :error
    end)

    result = Cake.main(["ls"])
    assert result == :error
  end

  test "target should start with a FROM" do
    Test.Support.write_cakefile("""
    target:
        RUN cmd
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg =~ "Validation error:"
      assert msg =~ "target doesn't start with a FROM command"
      :error
    end)

    result = Cake.main(["ls"])
    assert result == :error
  end

  test "@push target can only be terminal target" do
    Test.Support.write_cakefile("""
    target_1:
        @push
        FROM scratch

    target_2:
        FROM +target_1
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg =~ "Validation error:"
      assert msg =~ "push targets [\\\"target_1\\\"] can be only terminal target"
      :error
    end)

    result = Cake.main(["ls"])
    assert result == :error
  end
end
