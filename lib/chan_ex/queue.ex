defmodule ChanEx.Queue do
  @moduledoc """
  queue behavior
  """
  alias ChanEx.{DataQueue, WaiterQueue}

  @callback new(keyword()) :: DataQueue.t() | WaiterQueue.t()
end

defprotocol ChanEx.DataQueue do
  @moduledoc false

  @spec insert(t(), term()) :: t()
  def insert(q, item)

  @spec pop(t()) :: {:ok, {term(), t()}} | {:error, :empty}
  def pop(q)
end

defprotocol ChanEx.WaiterQueue do
  @moduledoc false

  @spec insert(t(), term()) :: t()
  def insert(q, item)

  @spec pop(t()) :: {:ok, {term(), t()}} | {:error, :empty}
  def pop(q)

  @spec empty?(t()) :: boolean()
  def empty?(q)

  @spec to_list(t()) :: list()
  def to_list(q)
end
