defmodule Dask.Limiter do
  # "Tricky point" about the limiter waiting_list (queue):
  #
  # When a process join the limiter asking "to wait its turn"
  # the limiter adds the process in FRONT of the queue (waiting_list is a LIFO queue).
  # This behaviour plays nice with the Dask DAG, since it startup the DAG in a reverse
  # topologically sorted order (why: see how it's implemented the Dask DAG ;)
  # So the last job joining the queue, the root job in the DAG, will be the first
  # to be served

  use GenServer
  require Logger

  @type t() :: nil | GenServer.server()
  @type max_concurrency :: pos_integer() | :infinity

  defmodule State do
    defstruct [:max_concurrency, :running_jobs, :waiting_list]

    @type t :: %__MODULE__{
            max_concurrency: non_neg_integer(),
            running_jobs: %{GenServer.server() => reference()},
            waiting_list: [{term(), GenServer.from()}]
          }
  end

  @spec start_link(max_concurrency()) :: {:ok, t()} | {:error, {:already_started, pid()} | term()}
  def start_link(max_concurrency, name \\ nil) do
    if max_concurrency == :infinity do
      {:ok, nil}
    else
      opts = if name, do: [name: name], else: []
      GenServer.start_link(__MODULE__, [max_concurrency], opts)
    end
  end

  @spec wait_my_turn(t(), term()) :: :ok
  def wait_my_turn(limiter, name \\ nil)
  def wait_my_turn(nil, _name), do: :ok
  def wait_my_turn(limiter, name), do: GenServer.call(limiter, {:wait_my_turn, name}, :infinity)

  @spec stats(t()) :: nil | [running: non_neg_integer(), waiting: non_neg_integer()]
  # coveralls-ignore-start
  def stats(nil), do: nil
  # coveralls-ignore-stop
  def stats(limiter), do: GenServer.call(limiter, :stats, :infinity)

  @impl true
  @spec init([non_neg_integer()]) :: {:ok, State.t()}
  def init([max_concurrency]) do
    {:ok, %State{max_concurrency: max_concurrency, running_jobs: %{}, waiting_list: []}}
  end

  @impl true
  def handle_call({:wait_my_turn, name}, {process, _} = from, %State{} = state) do
    Logger.debug("[process=#{inspect(process)}] (#{inspect(name)}) wait_my_turn #{inspect(state, pretty: true)}")

    if map_size(state.running_jobs) == state.max_concurrency do
      Logger.debug("[process=#{inspect(process)}] reached max_concurrency=#{state.max_concurrency}")
      Logger.debug("adding process to the waiting list")

      state = put_in(state.waiting_list, [{name, from} | state.waiting_list])
      {:noreply, state}
    else
      monitor = Process.monitor(process)

      state = put_in(state.running_jobs[process], monitor)
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:stats, _from, %State{} = state) do
    {:reply, [running: map_size(state.running_jobs), waiting: length(state.waiting_list)], state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, process, _reason}, %State{} = state) do
    Logger.debug("[process=#{inspect(process)}] job_end #{inspect(state, pretty: true)}")

    {_, state} = pop_in(state.running_jobs[process])

    state =
      if state.waiting_list != [] do
        [{waiting_job_name, waiting_job} | waiting_list] = state.waiting_list
        GenServer.reply(waiting_job, :ok)

        {waiting_process, _} = waiting_job
        Logger.debug("[process=#{inspect(waiting_process)}] (#{inspect(waiting_job_name)}) it's your turn")

        state = put_in(state.waiting_list, waiting_list)

        monitor = Process.monitor(waiting_process)
        put_in(state.running_jobs[waiting_process], monitor)
      else
        state
      end

    {:noreply, state}
  end
end
