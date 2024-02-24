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

    :ok
  end

  setup :verify_on_exit!

  defmacrop expect_container_build(target, n \\ 1, fun \\ nil) do
    quote do
      fun =
        if unquote(fun) do
          unquote(fun)
        else
          fn _target -> :ok end
        end

      expect(Test.ContainerManagerMock, :build, unquote(n), fn
        [],
        unquote(target) = target,
        _tags,
        _build_args,
        _containerfile_path,
        _no_cache,
        _secrets,
        _build_ctx,
        _pipeline_uuid ->
          fun.(target)
      end)
    end
  end

  test "empty Cakefile" do
    Test.Support.write_cakefile("""
    target:
        FROM scratch
    """)

    expect_container_build("target")

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

    expect_container_build("target", 1, fn _target ->
      Process.sleep(:infinity)
    end)

    {{result, _output}, stderr} =
      with_io(:stderr, fn ->
        {_result, _stdio} =
          with_io(fn ->
            Cake.main(["run", "--timeout", "1", "target"])
          end)
      end)

    assert result == :error
    assert stderr =~ "timeout"
  end

  test "crash" do
    Test.Support.write_cakefile("""
    target:
        FROM scratch
    """)

    expect_container_build("target", 1, fn _target ->
      raise "CRASH"
    end)

    {{result, _stdio}, stderr} =
      with_io(:stderr, fn ->
        {_result, _stdio} =
          with_io(fn ->
            Cake.main(["run", "target"])
          end)
      end)

    assert result == :error
    assert stderr =~ "job_skipped"
  end

  describe "run target with ARGS" do
    test "ok" do
      Test.Support.write_cakefile("""
      ARG global_arg1
      ARG global_arg2=default

      target:
          FROM scratch
          ARG target_arg1
          ARG target_arg2=default
      """)

      expect_container_build("target")

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "target", "global_arg1=g1", "target_arg1=t1"])
        end)

      assert result == :ok
    end

    test "bad_format" do
      Test.Support.write_cakefile("""

      target:
          FROM scratch
          ARG target_arg
      """)

      {result, stderr} =
        with_io(:stderr, fn ->
          Cake.main(["run", "target", "arg_bad_format"])
        end)

      assert result == :error
      assert stderr =~ "bad target argument: arg_bad_format"
    end
  end

  describe "run --progress" do
    test "plain" do
      Test.Support.write_cakefile("""
      target:
          FROM scratch
      """)

      expect_container_build("target")

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

      expect_container_build("target")

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "--progress", "interactive", "target"])
        end)

      assert result == :ok
    end
  end

  describe "targets dependencies" do
    test "cycle" do
      Test.Support.write_cakefile("""
      target_1:
          FROM +target_2

      target_2:
          FROM +target_3

      target_3:
          FROM +target_1
      """)

      {result, output} =
        with_io(:stderr, fn ->
          Cake.main(["run", "target_1"])
        end)

      assert result == :error

      expected_output = """
      Targets graph dependency error:
      "Targets cycle detected: target_3 -> target_2 -> target_1"
      """

      Test.Support.assert_output(output, expected_output)
    end

    test "unknown target" do
      Test.Support.write_cakefile("""
      target_1:
          FROM +target_unknown
      """)

      {result, output} =
        with_io(:stderr, fn ->
          Cake.main(["run", "target_1"])
        end)

      assert result == :error

      expected_output = """
      Targets graph dependency error:
      "Unknown target: target_unknown"
      """

      Test.Support.assert_output(output, expected_output)
    end

    test "FROM +target" do
      Test.Support.write_cakefile("""
      target_1:
          FROM scratch

      target_2:
          FROM +target_1
      """)

      expect_container_build("target_1")
      expect_container_build("target_2")

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "target_2"])
        end)

      assert result == :ok
    end

    test "COPY --from=+target" do
      Test.Support.write_cakefile("""
      target_1:
          FROM scratch
          RUN touch /file.txt

      target_2:
          FROM scratch
          COPY --from=+target_1 /file.txt /file.txt
      """)

      expect_container_build("target_1")
      expect_container_build("target_2")

      {result, _output} =
        with_io(fn ->
          Cake.main(["run", "target_2"])
        end)

      assert result == :ok
    end

    test "alias target" do
      test_pid = self()

      Test.Support.write_cakefile("""
      target_1:
          FROM scratch

      target_2:
          FROM scratch

      all: target_1 target_2
      """)

      expect_container_build(_, 2, fn target ->
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

    expect_container_build("target")

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
end
