defmodule ChanEx.ErlangQueue do
  @moduledoc """
  wrap erlang's :queue
  """
  @behaviour ChanEx.Queue

  @type t :: %__MODULE__{}

  defstruct q: nil

  @spec new(keyword()) :: t()
  def new(_), do: %__MODULE__{q: :queue.new()}

  @spec insert(t(), term()) :: t()
  def insert(%__MODULE__{q: q}, item), do: %__MODULE__{q: :queue.in(item, q)}

  @spec pop(t()) :: {:ok, {term(), t()}} | {:error, :empty}
  def pop(%__MODULE__{q: q}) do
    case :queue.out(q) do
      {{:value, v}, q} -> {:ok, {v, %__MODULE__{q: q}}}
      {:empty, _} -> {:error, :empty}
    end
  end

  @spec empty?(t()) :: boolean()
  def empty?(%__MODULE__{q: q}) do
    :queue.len(q) == 0
  end

  @spec to_list(t()) :: list()
  def to_list(%__MODULE__{q: q}) do
    :queue.to_list(q)
  end
end

defimpl ChanEx.DataQueue, for: ChanEx.ErlangQueue do
  @moduledoc false

  alias ChanEx.ErlangQueue

  defdelegate insert(q, item), to: ErlangQueue

  # def pop(q), do: ErlangQueue.pop(q)
  defdelegate pop(q), to: ErlangQueue
end

defimpl ChanEx.WaiterQueue, for: ChanEx.ErlangQueue do
  @moduledoc false

  alias ChanEx.ErlangQueue

  defdelegate insert(q, item), to: ErlangQueue

  # def pop(q), do: ErlangQueue.pop(q)
  defdelegate pop(q), to: ErlangQueue

  defdelegate empty?(q), to: ErlangQueue

  defdelegate to_list(q), to: ErlangQueue
end
