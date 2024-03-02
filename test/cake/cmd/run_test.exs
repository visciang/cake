defmodule Test.Cake.Cmd.Run do
  use ExUnit.Case, async: false

  alias Cake.Pipeline.Docker

  import ExUnit.CaptureIO
  import Mox
  require Test.Support

  @moduletag :tmp_dir
  setup {Test.Support, :setup_cake_run}

  setup do
    stub(Test.ContainerManagerMock, :fq_image, fn tgid, pipeline_uuid ->
      Docker.fq_image(tgid, pipeline_uuid)
    end)

    stub(Test.ContainerManagerMock, :fq_output_container, fn tgid, pipeline_uuid ->
      Docker.fq_output_container(tgid, pipeline_uuid)
    end)

    stub(Test.ContainerManagerMock, :cleanup, fn _ ->
      :ok
    end)

    stub(Test.SystemBehaviourMock, :halt, fn :ok, _ ->
      :ok
    end)

    :ok
  end

  setup :verify_on_exit!

  test "empty Cakefile" do
    Test.Support.write_cakefile("""
    target:
        FROM scratch
    """)

    expect_container_build(fn %{target: "target"} -> :ok end)

    {result, _output} =
      with_io(fn ->
        Cake.main(["run", "target"])
      end)

    assert result == :ok
  end

  test "timeout" do
    Test.Support.write_cakefile("""
    target:
        FROM scratch
    """)

    expect_container_build(fn %{target: "target"} ->
      Process.sleep(:infinity)
    end)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg == "timeout"
      :error
    end)

    {result, _stdio} =
      with_io(fn ->
        Cake.main(["run", "--timeout", "1", "target"])
      end)

    assert result == :error
  end

  test "crash" do
    Test.Support.write_cakefile("""
    target:
        FROM scratch
    """)

    expect_container_build(fn %{target: "target"} ->
      raise "CRASH"
    end)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg == :job_skipped
      :error
    end)

    {result, _stdio} =
      with_io(fn ->
        Cake.main(["run", "target"])
      end)

    assert result == :error
  end

  describe "push target" do
    test "without --push" do
      Test.Support.write_cakefile("""
      target:
          @push
          FROM scratch
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
        assert exit_status == :error
        assert msg == "@push target target can be executed only via 'run --push'"
        raise "HALT"
      end)

      assert_raise RuntimeError, "HALT", fn ->
        Cake.main(["run", "target"])
      end
    end

    test "basic" do
      Test.Support.write_cakefile("""
      target:
          @push
          FROM scratch
      """)

      expect_container_build(fn %{target: "target"} -> :ok end)

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "--push", "target"])
        end)

      assert result == :ok
    end
  end

  describe "target with ARGS" do
    test "ok" do
      Test.Support.write_cakefile("""
      ARG global_arg1
      ARG global_arg2=default

      target:
          FROM scratch
          ARG target_arg1
          ARG target_arg2=default
      """)

      expect_container_build(fn %{target: "target", build_args: [{"global_arg1", "g1"}, {"target_arg1", "t1"}]} ->
        :ok
      end)

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "target", "global_arg1=g1", "target_arg1=t1"])
        end)

      assert result == :ok
    end

    test "arguments bad_format" do
      Test.Support.write_cakefile("""

      target:
          FROM scratch
          ARG target_arg
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
        assert exit_status == :error
        assert msg == "bad target argument: arg_bad_format"
        :error
      end)

      result = Cake.main(["run", "target", "arg_bad_format"])
      assert result == :error
    end
  end

  describe "--progress" do
    test "plain" do
      Test.Support.write_cakefile("""
      target:
          FROM scratch
      """)

      expect_container_build(fn %{target: "target"} -> :ok end)

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "--progress", "plain", "target"])
        end)

      assert result == :ok
    end

    test "interactive" do
      Test.Support.write_cakefile("""
      target:
          FROM scratch
      """)

      expect_container_build(fn %{target: "target"} -> :ok end)

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "--progress", "interactive", "target"])
        end)

      assert result == :ok
    end
  end

  describe "targets dependencies" do
    test "with cycle" do
      Test.Support.write_cakefile("""
      target_1:
          FROM +target_2

      target_2:
          FROM +target_3

      target_3:
          FROM +target_1
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
        assert exit_status == :error
        assert msg =~ "Targets cycle detected: target_3 -> target_2 -> target_1"
        :error
      end)

      result = Cake.main(["run", "target_1"])
      assert result == :error
    end

    test "with unknown target" do
      Test.Support.write_cakefile("""
      target_1:
          FROM +target_unknown
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
        assert exit_status == :error
        assert msg =~ "Unknown target: target_unknown"
        :error
      end)

      result = Cake.main(["run", "target_1"])
      assert result == :error
    end

    test "via FROM +target" do
      Test.Support.write_cakefile("""
      target_1:
          FROM scratch

      target_2:
          FROM +target_1
      """)

      expect_container_build(fn %{target: "target_1"} -> :ok end)
      expect_container_build(fn %{target: "target_2"} -> :ok end)

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "target_2"])
        end)

      assert result == :ok
    end

    test "via COPY --from=+target" do
      Test.Support.write_cakefile("""
      target_1:
          FROM scratch
          RUN touch /file.txt

      target_2:
          FROM scratch
          COPY --from=+target_1 /file.txt /file.txt
      """)

      expect_container_build(fn %{target: "target_1"} -> :ok end)
      expect_container_build(fn %{target: "target_2"} -> :ok end)

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "target_2"])
        end)

      assert result == :ok
    end

    test "with alias target" do
      test_pid = self()

      Test.Support.write_cakefile("""
      target_1:
          FROM scratch

      target_2:
          FROM scratch

      all: target_1 target_2
      """)

      expect_container_build(2, fn %{target: target} ->
        send(test_pid, {:container_build, target})
        :ok
      end)

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "all"])
        end)

      assert result == :ok
      assert_received {:container_build, "target_1"}
      assert_received {:container_build, "target_2"}
    end
  end

  test "--output" do
    Test.Support.write_cakefile("""
    target:
        @output /output_1
        @output /output_2
        FROM scratch
        RUN touch /output_1/file_1.txt
        RUN touch /output_2/file_2.txt
    """)

    expect_container_build(fn %{target: "target"} -> :ok end)

    expect(Test.ContainerManagerMock, :output, fn
      [], "target", _pipeline_uuid, ["/output_1", "/output_2"], _output_dir ->
        :ok
    end)

    {result, _output} =
      with_io(fn ->
        Cake.main(["run", "--output", "target"])
      end)

    assert result == :ok
  end

  describe "--secret" do
    test "bad format" do
      Test.Support.write_cakefile("""
      target:
          FROM scratch
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, [msg] ->
        assert exit_status == :error
        assert msg =~ "invalid value \"bad_format\" for --secret option"
        :error
      end)

      result = Cake.main(["run", "--secret", "bad_format"])
      assert result == :error
    end
  end

  test "ok" do
    Test.Support.write_cakefile("""
    target:
        FROM scratch
        RUN --mount=type=secret,id=SECRET cat /run/secrets/SECRET
    """)

    expect_container_build(fn %{target: "target", secrets: ["id=SECRET,src=./secret"]} ->
      :ok
    end)

    {result, _output} =
      with_io(fn ->
        Cake.main(["run", "--secret", "id=SECRET,src=./secret", "target"])
      end)

    assert result == :ok
  end

  defp expect_container_build(n \\ 1, fun) do
    expect(Test.ContainerManagerMock, :build, n, fn
      ns, target, tags, build_args, containerfile_path, no_cache, secrets, build_ctx, pipeline_uuid ->
        args = %{
          ns: ns,
          target: target,
          tags: tags,
          build_args: build_args,
          containerfile_path: containerfile_path,
          no_cache: no_cache,
          secrets: secrets,
          build_ctx: build_ctx,
          pipeline_uuid: pipeline_uuid
        }

        fun.(args)
    end)
  end
end
