defmodule Test.Cake.Cmd.Run do
  use ExUnit.Case, async: false

  alias Cake.Pipeline.Docker

  import ExUnit.CaptureIO
  import Mox

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

  test "empty Cakefile" do
    Test.Support.write_cakefile("""
    target:
        FROM scratch
    """)

    expect(Test.ContainerManagerMock, :build, fn [],
                                                 "target",
                                                 _tags,
                                                 _build_args,
                                                 _containerfile_path,
                                                 _no_cache,
                                                 _secrets,
                                                 _build_ctx,
                                                 _pipeline_uuid ->
      :ok
    end)

    {result, _stdio} =
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

    expect(Test.ContainerManagerMock, :build, fn [],
                                                 "target",
                                                 _tags,
                                                 _build_args,
                                                 _containerfile_path,
                                                 _no_cache,
                                                 _secrets,
                                                 _build_ctx,
                                                 _pipeline_uuid ->
      Process.sleep(:infinity)
    end)

    {{result, _stdio}, stderr} =
      with_io(:stderr, fn ->
        {_result, _stdio} =
          with_io(fn ->
            Cake.main(["run", "--timeout", "1", "target"])
          end)
      end)

    assert result == :error
    assert stderr =~ "timeout"
  end
end
