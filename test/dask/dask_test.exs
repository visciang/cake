defmodule Test.Dask do
  use ExUnit.Case, async: true

  test "basic dask exec" do
    workflow_status = Dask.new() |> add_jobs() |> Dask.async() |> Dask.await(1_000)

    expected_workflow_execution = [
      job_a1: %{Dask.start_job_id() => :ok},
      job_a2: %{Dask.start_job_id() => :ok},
      job_a3: %{Dask.start_job_id() => :ok},
      job_err1: %{Dask.start_job_id() => :ok},
      job_b1: %{job_a1: :ok},
      job_c1: %{job_a1: :ok, job_a2: :ok, job_b1: :ok},
      job_c2: %{job_a3: :ok},
      job_d1: %{job_b1: :ok},
      job_d2: %{job_c1: :ok, job_c2: :ok}
    ]

    assert {:error, :job_skipped} == workflow_status
    assert_workflow_execution(expected_workflow_execution)
  end

  test "dask await returns the right final result" do
    test_job_fun_1 = gen_test_job_fun(fn -> :ok_1 end)
    test_job_fun_2 = gen_test_job_fun(fn -> :ok_2 end)
    test_job_fun_3 = gen_test_job_fun(fn -> :ok_3 end)

    workflow_status =
      Dask.new()
      |> Dask.job(:job_1, test_job_fun_1)
      |> Dask.job(:job_2, test_job_fun_2)
      |> Dask.job(:job_3, test_job_fun_3)
      |> Dask.flow(:job_1, :job_2)
      |> Dask.flow(:job_1, :job_3)
      |> Dask.async()
      |> Dask.await(1_000)

    expected_workflow_execution = [
      job_1: %{Dask.start_job_id() => :ok},
      job_2: %{:job_1 => :ok_1},
      job_3: %{:job_1 => :ok_1}
    ]

    assert {:ok, %{job_2: :ok_2, job_3: :ok_3}} == workflow_status
    assert_workflow_execution(expected_workflow_execution)
  end

  test "job timeout" do
    test_job_fun = gen_test_job_fun(fn -> :ok end)
    test_job_timeout_fun = gen_test_job_fun(fn -> Process.sleep(200) end)

    workflow_status =
      Dask.new()
      |> Dask.job(:job_1, test_job_timeout_fun, 100)
      |> Dask.job(:job_2, test_job_fun)
      |> Dask.flow(:job_1, :job_2)
      |> Dask.async()
      |> Dask.await(1_000)

    expected_workflow_execution = [
      job_1: %{Dask.start_job_id() => :ok}
    ]

    assert {:error, :job_skipped} = workflow_status
    assert_workflow_execution(expected_workflow_execution)
  end

  test "workflow timeout" do
    test_job_fun = gen_test_job_fun(fn -> :ok end)
    test_job_timeout_fun = gen_test_job_fun(fn -> Process.sleep(200) end)

    workflow_status =
      Dask.new()
      |> Dask.job(:job_1, test_job_timeout_fun)
      |> Dask.job(:job_2, test_job_fun)
      |> Dask.flow(:job_1, :job_2)
      |> Dask.async()
      |> Dask.await(100)

    assert workflow_status == :timeout
  end

  test "bad dask (deps cycle)" do
    test_job_fun = fn _, _ -> :ok end

    dask =
      Dask.new()
      |> Dask.job(:job_1, test_job_fun)
      |> Dask.job(:job_2, test_job_fun)
      |> Dask.depends_on(:job_2, :job_1)
      |> Dask.depends_on(:job_1, :job_2)

    assert_raise Dask.Error, fn ->
      Dask.async(dask)
    end
  end

  test "bad dask (unknown job)" do
    test_job_fun = fn _, _ -> :ok end

    dask =
      Dask.new()
      |> Dask.job(:job_1, test_job_fun)

    assert_raise Dask.Error, fn ->
      Dask.flow(dask, :job_1, :unknow_job)
    end

    assert_raise Dask.Error, fn ->
      Dask.flow(dask, :unknow_job, :job_1)
    end
  end

  test "dask to dot" do
    Dask.new()
    |> add_jobs()
    |> Dask.Dot.export()
  end

  defp add_jobs(dask) do
    test_job_fun = gen_test_job_fun(fn -> :ok end)
    test_job_error_fun = gen_test_job_fun(fn -> raise "Error" end)

    dask
    |> Dask.job(:job_a1, test_job_fun)
    |> Dask.job(:job_a2, test_job_fun)
    |> Dask.job(:job_a3, test_job_fun)
    |> Dask.job(:job_b1, test_job_fun)
    |> Dask.job(:job_c1, test_job_fun)
    |> Dask.job(:job_c2, test_job_fun)
    |> Dask.job(:job_d1, test_job_fun)
    |> Dask.job(:job_d2, test_job_fun)
    |> Dask.job(:job_err1, test_job_error_fun)
    |> Dask.job(:job_err2, test_job_fun)
    |> Dask.flow(:job_a1, [:job_b1, :job_c1])
    |> Dask.flow(:job_a2, :job_c1)
    |> Dask.flow(:job_a3, :job_c2)
    |> Dask.flow(:job_b1, [:job_c1, :job_d1])
    |> Dask.flow(:job_c1, :job_d2)
    |> Dask.flow(:job_c2, :job_d2)
    |> Dask.flow([:job_err1], :job_err2)
  end

  defp gen_test_job_fun(result_fun) do
    test_pid = self()

    fn job_id, upstream_jobs_status ->
      send(test_pid, {job_id, upstream_jobs_status})
      result_fun.()
    end
  end

  defp assert_workflow_execution(expected_workflow_execution) do
    for expected <- expected_workflow_execution, do: assert_received(^expected)

    receive do
      unexpected ->
        flunk("Unexpected dask execution: #{inspect(unexpected)}")
    after
      0 -> :ok
    end
  end
end
