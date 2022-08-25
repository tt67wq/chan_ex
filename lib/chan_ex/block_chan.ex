defmodule ChanEx.BlockState do
  @moduledoc false

  @type t :: %__MODULE__{
          capacity: non_neg_integer,
          size: non_neg_integer,
          data: ChanEx.DataQueue.t(),
          wait_state: :idle | :push | :pop,
          waiters: ChanEx.WaiterQueue.t()
        }

  defstruct capacity: 0,
            size: 0,
            data: nil,
            wait_state: :idle,
            waiters: nil

  def new(max, dataq, waiterq),
    do: %__MODULE__{
      capacity: max,
      size: 0,
      data: dataq.new([]),
      wait_state: :idle,
      waiters: waiterq.new([])
    }
end

defmodule ChanEx.BlockChan do
  @moduledoc false
  use GenServer

  alias ChanEx.BlockState, as: State

  alias ChanEx.{DataQueue, WaiterQueue}

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
       Application.get_env(:chan_ex, :data_queue_impl, ChanEx.ErlangQueue),
       Application.get_env(:chan_ex, :waiter_queue_impl, ChanEx.ErlangQueue)
     )}
  end

  # start a list of waiting pushers when the first client tries to push to a full queue
  def handle_call({:bpush, item}, from, %State{capacity: max, size: n, waiters: w} = s)
      when n >= max do
    {:reply, :block,
     %{s | size: n + 1, waiters: WaiterQueue.insert(w, {:push, {from, item}}), wait_state: :push}}
  end

  def handle_call({:bpush, item}, _, %State{wait_state: :pop, waiters: w} = s) do
    {:ok, {{:pop, pop_waiter}, nw}} = WaiterQueue.pop(w)
    notify(pop_waiter, {:awaken, item})

    wait_state =
      if WaiterQueue.empty?(nw) do
        :idle
      else
        :pop
      end

    {:reply, nil, %{s | waiters: nw, wait_state: wait_state}}
  end

  def handle_call({:bpush, item}, _, %State{data: q, size: n, wait_state: :idle} = s) do
    {:reply, nil, %{s | size: n + 1, data: DataQueue.insert(q, item)}}
  end

  def handle_call({:push, _item}, _, %State{wait_state: :push} = s) do
    {:reply, :full, s}
  end

  def handle_call({:push, _}, _, %State{capacity: max, size: n} = s) when n >= max,
    do: {:reply, :full, s}

  def handle_call({:push, item}, from, s) do
    handle_call({:bpush, item}, from, s)
  end

  # start a list of waiting poppers when the first client tries to pop from the empty queue

  def handle_call(:bpop, from, %State{size: 0, waiters: w} = s) do
    {:reply, :block, %{s | waiters: WaiterQueue.insert(w, {:pop, from}), wait_state: :pop}}
  end

  def handle_call(:bpop, _, %State{data: q, wait_state: :push, waiters: w, size: n} = s) do
    {:ok, {item, nq}} = DataQueue.pop(q)
    {:ok, {{:push, {push_waiter, wait_item}}, nw}} = WaiterQueue.pop(w)
    notify(push_waiter, :awaken)
    {:reply, item, %{s | data: DataQueue.insert(nq, wait_item), waiters: nw, size: n - 1}}
  end

  def handle_call(:bpop, _, %State{data: q, size: n} = s) do
    {:ok, {item, nq}} = DataQueue.pop(q)
    {:reply, item, %{s | size: n - 1, data: nq}}
  end

  def handle_call(:pop, _, %State{wait_state: :pop} = s) do
    {:reply, :empty, s}
  end

  def handle_call(:pop, _, %State{size: 0} = s) do
    {:reply, :empty, s}
  end

  def handle_call(:pop, from, s), do: handle_call(:bpop, from, s)

  # determine is the queue is empty
  def handle_call(:is_empty, _, s) do
    {:reply, s.size == 0, s}
  end

  def handle_call(:is_full, _, s) do
    {:reply, s.size >= s.capacity, s}
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

  defp cleanup(_, %State{waiters: w}) do
    Task.async_stream(
      WaiterQueue.to_list(w),
      fn
        {:pop, pop_waiter} ->
          notify(pop_waiter, :closed)

        {:push, {push_waiter, _}} ->
          notify(push_waiter, :closed)
      end,
      max_conwait_stateency: 50
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
  @spec bpush(pid, any, integer) :: :ok
  def bpush(pid, item, timeout \\ 5000) do
    case GenServer.call(pid, {:bpush, item}, timeout) do
      :block ->
        receive do
          :awaken -> :ok
          :closed -> {:error, :closed}
        end

      _ ->
        :ok
    end
  end

  @spec push(pid, term(), non_neg_integer) :: :ok | {:error, :full}
  def push(pid, item, timeout \\ 5000) do
    case GenServer.call(pid, {:push, item}, timeout) do
      :full -> {:error, :full}
      _ -> :ok
    end
  end

  @spec push!(pid, any, non_neg_integer) :: :ok
  def push!(pid, item, timeout \\ 5000) do
    push(pid, item, timeout)
    |> case do
      :ok -> :ok
      _ -> raise "channel is full"
    end
  end

  @doc """
  Pops the least recently pushed item from the queue. Blocks if the queue is
  empty until an item is available.

  `pid` is the process ID of the BlockChan server.
  `timeout` (optional) is the timeout value passed to GenServer.call (does not impact how long pop will wait for a message from the queue)
  """
  @spec bpop(pid, integer) :: any
  def bpop(pid, timeout \\ 5000) do
    case GenServer.call(pid, :bpop, timeout) do
      :block ->
        receive do
          {:awaken, data} -> data
          :closed -> {:error, :closed}
        end

      data ->
        data
    end
  end

  @spec pop(pid, integer) :: term() | {:error, :empty}
  def pop(pid, timeout \\ 5000) do
    case GenServer.call(pid, :pop, timeout) do
      :empty -> {:error, :empty}
      item -> item
    end
  end

  @spec pop!(pid, non_neg_integer) :: any
  def pop!(pid, timeout \\ 5000) do
    pop(pid, timeout)
    |> case do
      {:error, :empty} -> raise "channel is empty"
      item -> item
    end
  end

  @doc """
  Tests if the queue is empty and returns true if so, otherwise false.

  `pid` is the process ID of the BlockChan server.
  """
  @spec empty?(pid, integer) :: boolean
  def empty?(pid, timeout \\ 5000) do
    GenServer.call(pid, :is_empty, timeout)
  end

  @spec full?(pid, integer) :: boolean
  def full?(pid, timeout \\ 5000) do
    GenServer.call(pid, :is_full, timeout)
  end

  @doc """
  Calculates and returns the number of items in the queue.

  `pid` is the process ID of the BlockChan server.
  """
  @spec size(pid, integer) :: non_neg_integer
  def size(pid, timeout \\ 5000) do
    GenServer.call(pid, :len, timeout)
  end

  @spec close(atom | pid | {atom, any} | {:via, atom, any}) :: :ok
  def close(pid) do
    GenServer.stop(pid)
  end
end
