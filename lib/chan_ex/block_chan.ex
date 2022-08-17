defmodule ChanEx.BlockState do
  @moduledoc false

  @type t :: %__MODULE__{
          capacity: non_neg_integer,
          size: non_neg_integer,
          data: ChanEx.Queue.t(),
          idata: :atom,
          curr: :idle | :push | :pop,
          waiters: ChanEx.Queue.t(),
          iwaiter: :atom
        }

  defstruct capacity: 0,
            size: 0,
            data: nil,
            idata: nil,
            curr: :idle,
            waiters: nil,
            iwaiter: nil

  def new(max, dataq, waiterq),
    do: %__MODULE__{
      capacity: max,
      size: 0,
      data: dataq.new(),
      idata: dataq,
      curr: :idle,
      waiters: waiterq.new(),
      iwaiter: waiterq
    }
end

defmodule ChanEx.BlockChan do
  @moduledoc false
  use GenServer

  alias ChanEx.BlockState, as: State

  @opt_schema [
    capacity: [
      type: :non_neg_integer,
      default: 256,
      doc: "max number of items can be pushed into the chan before blocked"
    ],
    name: [
      type: :any,
      default: __MODULE__,
      doc: "name of block chan"
    ]
  ]

  def start_link(opts) do
    opts = NimbleOptions.validate!(opts, @opt_schema)
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @spec init(keyword) :: {:ok, ChanEx.BlockState.t()}
  def init(opts) do
    Process.flag(:trap_exit, true)

    {:ok,
     State.new(
       opts[:capacity],
       Application.get_env(:chan_ex, :data_queue_impl, ChanEx.ConstantQueue),
       Application.get_env(:chan_ex, :data_queue_impl, ChanEx.ConstantQueue)
     )}
  end

  defp dataq(s), do: s.idata
  defp waiterq(s), do: s.iwaiter

  # start a list of waiting pushers when the first client tries to push to a full queue
  def handle_call({:push, item}, from, %State{capacity: max, size: n, waiters: w} = s)
      when n >= max do
    {:reply, :block,
     %{s | size: n + 1, waiters: dataq(s).insert(w, {:push, {from, item}}), curr: :push}}
  end

  def handle_call({:push, item}, _, %State{size: 0, curr: :pop, waiters: w} = s) do
    {:ok, {{:pop, pop_waiter}, nw}} = waiterq(s).pop(w)
    notify(pop_waiter, {:awaken, item})

    curr =
      if waiterq(s).empty?(nw) do
        :idle
      else
        :pop
      end

    {:reply, nil, %{s | waiters: nw, curr: curr}}
  end

  def handle_call({:push, item}, _, %State{data: q, size: n, curr: :idle} = s) do
    {:reply, nil, %{s | size: n + 1, data: dataq(s).insert(q, item)}}
  end

  # start a list of waiting poppers when the first client tries to pop from the empty queue

  def handle_call(:pop, from, %State{size: 0, waiters: w} = s) do
    {:reply, :block, %{s | waiters: waiterq(s).insert(w, {:pop, from}), curr: :pop}}
  end

  def handle_call(:pop, _, %State{data: q, curr: :push, waiters: w, size: n} = s) do
    {:ok, {item, nq}} = dataq(s).pop(q)
    {:ok, {{:push, {push_waiter, wait_item}}, nw}} = waiterq(s).pop(w)
    notify(push_waiter, :awaken)
    {:reply, item, %{s | data: dataq(s).insert(nq, wait_item), waiters: nw, size: n - 1}}
  end

  def handle_call(:pop, _, %State{data: q, size: n} = s) do
    {:ok, {item, nq}} = dataq(s).pop(q)
    {:reply, item, %{s | size: n - 1, data: nq}}
  end

  # determine is the queue is empty
  def handle_call(:is_empty, _, s) do
    {:reply, s.size == 0, s}
  end

  # determine the length of the queue
  def handle_call(:len, _, s) do
    {:reply, s.size, s}
  end

  def handle_info({:EXIT, _from, reason}, state) do
    cleanup(reason, state)
    {:stop, reason, state}
  end

  def terminate(reason, state) do
    cleanup(reason, state)
    state
  end

  defp cleanup(_, %State{waiters: w} = s) do
    Task.async_stream(
      waiterq(s).to_list(w),
      fn
        {:pop, pop_waiter} ->
          notify(pop_waiter, :closed)

        {:push, {push_waiter, _}} ->
          notify(push_waiter, :closed)
      end,
      max_concurrency: 50
    )
    |> Stream.run()
  end

  defp notify({pid, _}, msg), do: notify(pid, msg)

  defp notify(pid, msg) do
    if Process.alive?(pid) do
      send(pid, msg)
    end
  end

  @doc """
  Pushes a new item into the queue.  Blocks if the queue is full.

  `pid` is the process ID of the BlockChan server.
  `item` is the value to be pushed into the queue.  This can be anything.
  `timeout` (optional) is the timeout value passed to GenServer.call (does not impact how long pop will wait for a message from the queue)
  """
  @spec push(pid, any, integer) :: :ok
  def push(pid, item, timeout \\ 5000) do
    case GenServer.call(pid, {:push, item}, timeout) do
      :block ->
        receive do
          :awaken -> :ok
          :closed -> {:error, :closed}
        end

      _ ->
        :ok
    end
  end

  @doc """
  Pops the least recently pushed item from the queue. Blocks if the queue is
  empty until an item is available.

  `pid` is the process ID of the BlockChan server.
  `timeout` (optional) is the timeout value passed to GenServer.call (does not impact how long pop will wait for a message from the queue)
  """
  @spec pop(pid, integer) :: any
  def pop(pid, timeout \\ 5000) do
    case GenServer.call(pid, :pop, timeout) do
      :block ->
        receive do
          {:awaken, data} -> data
          :closed -> {:error, :closed}
        end

      data ->
        data
    end
  end

  @doc """
  Pushes all items in a stream into the blocking queue.  Blocks as necessary.

  `stream` is the the stream of values to push into the queue.
  `pid` is the process ID of the BlockChan server.
  """
  @spec push_stream(Enumerable.t(), pid) :: nil
  def push_stream(pid, stream) do
    spawn_link(fn ->
      Enum.each(stream, &push(pid, &1))
    end)

    nil
  end

  @doc """
  Returns a Stream where each element comes from the BlockChan.

  `pid` is the process ID of the BlockChan server.
  """
  @spec pop_stream(pid) :: Enumerable.t()
  def pop_stream(pid) do
    Stream.repeatedly(fn -> pop(pid) end)
  end

  @doc """
  Tests if the queue is empty and returns true if so, otherwise false.

  `pid` is the process ID of the BlockChan server.
  """
  @spec empty?(pid, integer) :: boolean
  def empty?(pid, timeout \\ 5000) do
    GenServer.call(pid, :is_empty, timeout)
  end

  @doc """
  Calculates and returns the number of items in the queue.

  `pid` is the process ID of the BlockChan server.
  """
  @spec size(pid, integer) :: non_neg_integer
  def size(pid, timeout \\ 5000) do
    GenServer.call(pid, :len, timeout)
  end

  def close(pid) do
    GenServer.stop(pid)
  end
end
