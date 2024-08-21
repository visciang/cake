defmodule Test.Cake.Validator do
  use ExUnit.Case, async: false

  import Mox

  @moduletag :tmp_dir

  setup {Test.Support, :setup_cake_run}

  describe "alias targets cannot be referenced in" do
    test "FROM instructions" do
      Test.Support.write_cakefile("""
      alias_target: target_1

      target_1:
          FROM scratch

      target_2:
          FROM +alias_target
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

    test "COPY instructions" do
      Test.Support.write_cakefile("""
      alias_target: target_1

      target_1:
          FROM scratch

      target_2:
          FROM scratch
          COPY --from=+alias_target xxx
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
  end

  describe "local targets cannot be referenced in" do
    test "FROM instructions" do
      Test.Support.write_cakefile("""
      local_target:
          LOCAL /bin/sh
          echoi "Hello"

      target_2:
          FROM +local_target
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
        assert exit_status == :error
        assert msg =~ "Validation error:"
        assert msg =~ "local targets [\\\"local_target\\\"] cannot be referenced in FROM/COPY instructions"
        :error
      end)

      result = Cake.main(["ls"])
      assert result == :error
    end

    test "COPY instructions" do
      Test.Support.write_cakefile("""
      local_target:
          LOCAL /bin/sh
          echo "Hello"

      target_2:
          FROM scratch
          COPY --from=+local_target xxx
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
        assert exit_status == :error
        assert msg =~ "Validation error:"
        assert msg =~ "local targets [\\\"local_target\\\"] cannot be referenced in FROM/COPY instructions"
        :error
      end)

      result = Cake.main(["ls"])
      assert result == :error
    end
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
