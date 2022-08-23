# ChanEx
<!-- MDOC !-->

This is a blocking channel implementation in Elixir. When I code in Elixir, I often wondering if there is a queue like *chan* in Go, so I made one.

## Usage

In Go, code like this can be seen everywhere:

```go
var a chan struct{}

func foo() {
  fmt.Println("aha!")
  a <- struct{}{}
}

func main() {
  a = make(chan struct{}, 1)
  go foo()
  <-a
}
```

with *ChanEx*, you can write Elixir code in Go style:

```elixir
iex> ChanEx.start_link(name: :demo)
iex> {:ok, chan} = ChanEx.get_chan(:demo, :foo)
iex> ChanEx.bpush(chan, "ops")
:ok
# pop alter to be running in another process
iex> ChanEx.bpop(chan)
"ops"
```

## Customize
ChanEx depends on Queue implementation for both data and waiter, you can configure your own queue implentation via:

```elixir
config :chan_ex, 
  data_queue_impl: YourDataQueueImpl,
  waiter_queue_impl: YourWaiterQueueImpl
```

Your implementation must the obey the following behavior:

```elixir
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
```

You can event make this channel distributed by implementation using third-part storage like Redis.