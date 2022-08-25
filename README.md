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

Your implementation must the obey the following protocols:

```elixir
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

```

You can event make this channel distributed by implementation using third-part storage like Redis.