defmodule ChanEx.BlockState do
  @moduledoc false

  alias ChanEx.ConstantQueue

  @type t :: %__MODULE__{
          capacity: non_neg_integer,
          size: non_neg_integer,
          queue: ConstantQueue.t(),
          curr: :idle | :push | :pop,
          waiters: ConstantQueue.t()
        }

  defstruct capacity: 0,
            size: 0,
            queue: nil,
            curr: :idle,
            waiters: nil

  def new(max),
    do: %__MODULE__{
      capacity: max,
      size: 0,
      queue: ConstantQueue.new(),
      curr: :idle,
      waiters: ConstantQueue.new()
    }
end

defmodule ChanEx.BlockChan do
  @moduledoc false
  use GenServer

  alias ChanEx.BlockState, as: State
  alias ChanEx.ConstantQueue, as: Queue

  defstruct pid: nil
  @type t :: %__MODULE__{pid: pid()}

  @type on_start :: {:ok, pid} | :ignore | {:error, {:already_started, pid} | term}

  def start_link({n, name}), do: GenServer.start_link(__MODULE__, n, name: name)

  @spec init(any) :: {:ok, ChanEx.BlockState.t()}
  def init(n) do
    Process.flag(:trap_exit, true)
    {:ok, State.new(n)}
  end

  # start a list of waiting pushers when the first client tries to push to a full queue
  def handle_call({:push, item}, from, %State{capacity: max, size: n, waiters: w} = s)
      when n >= max do
    {:reply, :block,
     %{s | size: n + 1, waiters: Queue.insert(w, {:push, {from, item}}), curr: :push}}
  end

  def handle_call({:push, item}, _, %State{size: 0, curr: :pop, waiters: w} = s) do
    {:ok, {{:pop, pop_waiter}, nw}} = Queue.pop(w)
    send(elem(pop_waiter, 0), {:awaken, item})

    curr =
      if Queue.empty?(nw) do
        :idle
      else
        :pop
      end

    {:reply, nil, %{s | waiters: nw, curr: curr}}
  end

  def handle_call({:push, item}, _, %State{queue: q, size: n, curr: :idle} = s) do
    {:reply, nil, %{s | size: n + 1, queue: Queue.insert(q, item)}}
  end

  # start a list of waiting poppers when the first client tries to pop from the empty queue

  def handle_call(:pop, from, %State{size: 0, waiters: w} = s) do
    {:reply, :block, %{s | waiters: Queue.insert(w, {:pop, from}), curr: :pop}}
  end

  def handle_call(:pop, _, %State{queue: q, curr: :push, waiters: w, size: n} = s) do
    {:ok, {item, nq}} = Queue.pop(q)
    {:ok, {{:push, {push_waiter, wait_item}}, nw}} = Queue.pop(w)
    send(elem(push_waiter, 0), :awaken)
    {:reply, item, %{s | queue: Queue.insert(nq, wait_item), waiters: nw, size: n - 1}}
  end

  def handle_call(:pop, _, %State{queue: q, size: n} = s) do
    {:ok, {item, nq}} = Queue.pop(q)
    {:reply, item, %{s | size: n - 1, queue: nq}}
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

  defp cleanup(_, %State{waiters: w}) do
    w
    |> Queue.to_list()
    |> Enum.each(fn
      {:pop, pop_waiter} ->
        send(elem(pop_waiter, 0), :closed)

      {:push, {push_waiter, _}} ->
        send(elem(push_waiter, 0), :closed)
    end)
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
  def push_stream(stream, pid) do
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
