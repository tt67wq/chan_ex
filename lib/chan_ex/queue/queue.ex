defmodule ChanEx.QueueImpl do
  @moduledoc false

  @type t :: term()
  defmodule Data do
    @type queue :: ChanEx.QueueImpl.t()

    @callback new(keyword()) :: queue()
    @callback insert(queue(), term()) :: queue()
    @callback pop(queue()) :: {:ok, {term(), queue()}} | {:error, :empty}
  end

  defmodule Waiter do
    @type queue :: ChanEx.QueueImpl.t()

    @callback new(keyword()) :: queue()
    @callback empty?(queue()) :: boolean()
    @callback insert(queue(), term()) :: queue()
    @callback pop(queue()) :: {:ok, {term(), queue()}} | {:error, :empty}
    @callback to_list(queue()) :: list()
  end
end

defmodule ChanEx.ErlangQueue do
  @moduledoc """
  wrap erlang's :queue to ChanEx.QueueImpl
  """

  def new(_), do: :queue.new()

  def insert(q, item), do: :queue.in(item, q)

  def pop(q) do
    case :queue.out(q) do
      {{:value, v}, q} -> {:ok, {v, q}}
      {:empty, _} -> {:error, :empty}
    end
  end

  def empty?(q) do
    :queue.len(q) == 0
  end

  def to_list(q) do
    :queue.to_list(q)
  end
end
