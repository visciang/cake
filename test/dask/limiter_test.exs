defmodule DakeTest.Dask.Limiter do
  use ExUnit.Case, async: true

  alias Dask

  test "workflow limiter" do
    max_concurrency = 2
    {:ok, wl} = Dask.Limiter.start_link(max_concurrency)

    t1 = start_task(wl, :t1)
    assert_task_ready(t1)

    t2 = start_task(wl, :t2)
    assert_task_ready(t2)

    t3 = start_task(wl, :t3)
    assert_task_not_ready(t3)

    proceed_with_task(t3)
    assert_task_not_proceeding(t3)

    proceed_with_task(t2)
    assert_task_done(t2)
    assert_task_done(t3)

    proceed_with_task(t1)
    assert_task_done(t1)

    assert_limiter_converge_to_zero_running_jobs(wl)
  end

  defp start_task(workflow_limiter, task_id) do
    test_pid = self()

    {:ok, pid} =
      Task.start_link(fn ->
        send(test_pid, {task_id, :up})

        :ok = Dask.Limiter.wait_my_turn(workflow_limiter)

        send(test_pid, {task_id, :ready})

        receive do
          :proceed -> send(test_pid, {task_id, :done})
        end
      end)

    # wait task is up
    assert_receive {^task_id, :up}

    {task_id, pid}
  end

  defp proceed_with_task({_task_id, task_pid}) do
    send(task_pid, :proceed)
  end

  defp assert_task_not_proceeding({task_id, _task_pid}) do
    refute_receive {^task_id, :done}
  end

  defp assert_task_ready({task_id, _task_pid}) do
    assert_receive {^task_id, :ready}
  end

  defp assert_task_not_ready({task_id, _task_pid}) do
    refute_receive {^task_id, :ready}
  end

  defp assert_task_done({task_id, _task_pid}) do
    assert_receive {^task_id, :done}
  end

  defp assert_limiter_converge_to_zero_running_jobs(wl, retry \\ 3, retry_period \\ 100) do
    if retry == 0 do
      flunk("Dask limiter didn't reach zero running jobs")
    end

    wl
    |> Dask.Limiter.stats()
    |> case do
      [running: 0, waiting: 0] ->
        :ok

      _ ->
        Process.sleep(retry_period)
        assert_limiter_converge_to_zero_running_jobs(wl, retry - 1)
    end
  end
end
