defmodule Test.Cake.Run do
  use ExUnit.Case, async: false

  require Logger
  alias Cake.Parser.Target.Local
  alias Cake.Pipeline.Docker

  import ExUnit.CaptureIO
  import Mox
  require Test.Support

  @moduletag :tmp_dir
  setup {Test.Support, :setup_cake_run}

  setup do
    stub(Test.ContainerMock, :fq_image, fn tgid, pipeline_uuid ->
      Docker.fq_image(tgid, pipeline_uuid)
    end)

    stub(Test.ContainerMock, :fq_output_container, fn tgid, pipeline_uuid ->
      Docker.fq_output_container(tgid, pipeline_uuid)
    end)

    stub(Test.ContainerMock, :cleanup, fn _ ->
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
      raise "HALT"
    end)

    assert_raise RuntimeError, "HALT", fn ->
      with_io(fn ->
        Cake.main(["run", "--timeout", "1", "target"])
      end)
    end
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

  test "target not present -> did you mean?" do
    Test.Support.write_cakefile("""
    foo:
        FROM scratch

    bar:
        FROM scratch
    """)

    expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
      assert exit_status == :error
      assert msg == "Did you mean 'foo'?'"
      raise "HALT"
    end)

    assert_raise RuntimeError, "HALT", fn ->
      with_io(fn ->
        Cake.main(["run", "foi"])
      end)
    end
  end

  describe "push target" do
    test "ok" do
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
        with_io(fn ->
          Cake.main(["run", "target"])
        end)
      end
    end
  end

  describe "local target" do
    test "ok" do
      Test.Support.write_cakefile("""
      ARG global_arg1
      ARG global_arg2=default

      target:
          LOCAL /bin/sh -c
          ARG target_arg1
          ARG target_arg2=default
          echo "Test"
      """)

      expect_local_run(fn %{
                            local: %Local{tgid: "target"},
                            env: %{
                              "global_arg1" => "g1",
                              "global_arg2" => "default",
                              "target_arg1" => "t1"
                            }
                          } ->
        :ok
      end)

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "target", "global_arg1=g1", "target_arg1=t1"])
        end)

      assert result == :ok
    end

    test "incompatible run flag: --shell" do
      Test.Support.write_cakefile("""
      foo:
          LOCAL /bin/sh -c
          echo "test"
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
        assert exit_status == :error
        assert msg == "Flag --shell is not allowed for LOCAL targets"
        raise "HALT"
      end)

      assert_raise RuntimeError, "HALT", fn ->
        with_io(fn ->
          Cake.main(["run", "--shell", "foo"])
        end)
      end
    end

    test "incompatible run options: --tag" do
      Test.Support.write_cakefile("""
      foo:
          LOCAL /bin/sh -c
          echo "test"
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
        assert exit_status == :error
        assert msg == "Option --tag is not allowed for LOCAL targets"
        raise "HALT"
      end)

      assert_raise RuntimeError, "HALT", fn ->
        with_io(fn ->
          Cake.main(["run", "--tag", "tag-test", "foo"])
        end)
      end
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
        raise "HALT"
      end)

      assert_raise RuntimeError, "HALT", fn ->
        with_io(fn ->
          Cake.main(["run", "target", "arg_bad_format"])
        end)
      end
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
        raise "HALT"
      end)

      assert_raise RuntimeError, "HALT", fn ->
        with_io(fn ->
          Cake.main(["run", "target_1"])
        end)
      end
    end

    test "with unknown target" do
      Test.Support.write_cakefile("""
      target_1:
          FROM +target_unknown
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
        assert exit_status == :error
        assert msg =~ "Unknown target: target_unknown"
        raise "HALT"
      end)

      assert_raise RuntimeError, "HALT", fn ->
        with_io(fn ->
          Cake.main(["run", "target_1"])
        end)
      end
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

    test "explicit target dep" do
      Test.Support.write_cakefile("""
      target_1:
          FROM scratch

      target_2: target_1
          FROM scratch
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

  describe "--output" do
    test "multiples" do
      Test.Support.write_cakefile("""
      target:
          @output /output_1
          @output /output_2
          FROM scratch
          RUN touch /output_1/file_1.txt
          RUN touch /output_2/file_2.txt
      """)

      expect_container_build(fn %{target: "target"} -> :ok end)

      expect(Test.ContainerMock, :output, fn
        "target", _pipeline_uuid, ["/output_1", "/output_2"], _output_dir ->
          :ok
      end)

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "--output", "target"])
        end)

      assert result == :ok
    end

    test "with variable interpolation" do
      Test.Support.write_cakefile("""
      target:
          @output /$ARG_1/${ARG_2}/output
          FROM scratch
      """)

      expect_container_build(fn %{target: "target"} -> :ok end)

      expect(Test.ContainerMock, :output, fn
        "target", _pipeline_uuid, ["/arg_1/arg_2/output"], _output_dir ->
          :ok
      end)

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "--output", "target", "ARG_1=arg_1", "ARG_2=arg_2"])
        end)

      assert result == :ok
    end
  end

  describe "--secret" do
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

    test "bad format" do
      Test.Support.write_cakefile("""
      target:
          FROM scratch
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, [msg] ->
        assert exit_status == :error
        assert msg =~ "invalid value \"bad_format\" for --secret option"
        raise "HALT"
      end)

      assert_raise RuntimeError, "HALT", fn ->
        with_io(fn ->
          Cake.main(["run", "--secret", "bad_format"])
        end)
      end
    end
  end

  describe "include" do
    test "with included Cakefile error" do
      Test.Support.write_cakefile("dir", """
      inc_target:
          invalid!
      """)

      Test.Support.write_cakefile("""
      @include dir

      target:
          FROM scratch
      """)

      expect(Test.SystemBehaviourMock, :halt, fn exit_status, msg ->
        assert exit_status == :error
        assert msg =~ "Cakefile syntax error at dir/Cakefile"
        raise "HALT"
      end)

      assert_raise RuntimeError, "HALT", fn ->
        with_io(fn ->
          Cake.main(["run", "target"])
        end)
      end
    end
  end

  defp expect_container_build(n \\ 1, fun) do
    expect(Test.ContainerMock, :build, n, fn
      target, tags, build_args, containerfile_path, no_cache, secrets, build_ctx, pipeline_uuid ->
        args = %{
          target: target,
          tags: tags,
          build_args: build_args,
          containerfile_path: containerfile_path,
          no_cache: no_cache,
          secrets: secrets,
          build_ctx: build_ctx,
          pipeline_uuid: pipeline_uuid
        }

        require Logger

        try do
          fun.(args)
        rescue
          exception ->
            Logger.error("expect_container_build FAILED - args: #{inspect(args)}")
            reraise exception, __STACKTRACE__
        end
    end)
  end

  defp expect_local_run(n \\ 1, fun) do
    expect(Test.LocalMock, :run, n, fn
      %Local{} = local, env, pipeline_uuid ->
        args = %{
          local: local,
          env: env,
          pipeline_uuid: pipeline_uuid
        }

        try do
          fun.(args)
        rescue
          exception ->
            Logger.error("expect_local_run FAILED - args: #{inspect(args)}")
            reraise exception, __STACKTRACE__
        end
    end)
  end
end
