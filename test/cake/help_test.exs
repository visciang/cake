defmodule Test.Cake.Help do
  use ExUnit.Case, async: false

  import Mox
  require Test.Support

  @moduletag :tmp_dir
  setup {Test.Support, :setup_cake_run}

  test "--version" do
    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :ok
      assert msg =~ "cake (Container-mAKE pipeline) 0.0.0"
      :ok
    end)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :ok
      assert msg == nil
      :ok
    end)

    result = Cake.main(["--version"])
    assert result == :ok
  end

  test "--help" do
    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :ok
      assert msg =~ "cake (Container-mAKE pipeline) 0.0.0"
      assert msg =~ "USAGE:"
      :ok
    end)

    result = Cake.main(["--help"])
    assert result == :ok
  end

  test "subcommand" do
    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :ok
      assert msg =~ "Run the pipeline"
      :ok
    end)

    result = Cake.main(["help", "run"])
    assert result == :ok
  end

  test "no args" do
    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :ok
      assert msg =~ "cake (Container-mAKE pipeline) 0.0.0"
      assert msg =~ "USAGE:"
      :ok
    end)

    result = Cake.main([])
    assert result == :ok
  end
end
