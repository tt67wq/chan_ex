defmodule ChanEx.Queue do
  @moduledoc false

  @type t :: term()
  defmodule Data do
    @type queue :: ChanEx.Queue.t()

    @callback new(keyword()) :: queue()
    @callback size(queue()) :: non_neg_integer()
    @callback empty?(queue()) :: boolean()
    @callback insert(queue(), term()) :: queue()
    @callback pop(queue()) :: {:ok, {term(), queue()}} | {:error, any}
  end

  defmodule Waiter do
    @type queue :: ChanEx.Queue.t()

    @callback new(keyword()) :: queue()
    @callback empty?(queue()) :: boolean()
    @callback insert(queue(), term()) :: queue()
    @callback pop(queue()) :: {:ok, {term(), queue()}} | {:error, any}
    @callback to_list(queue()) :: list()
  end
end
