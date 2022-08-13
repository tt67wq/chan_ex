defmodule ChanExTest do
  use ExUnit.Case
  doctest ChanEx

  setup do
    {:ok, _} = ChanEx.start_link(name: :test)
    {:ok, []}
  end

  test "producer and consumer", _ do
    {:ok, q} = ChanEx.get_chan(:test, "q", 5)

    {:ok, stop} = ChanEx.get_chan(:test, "stop")
    spawn(fn -> producer(q, stop, 1) end)
    spawn(fn -> consumer(q) end)

    # wait stop
    ChanEx.pop(stop)
    ChanEx.close(q)
    ChanEx.close(stop)
    IO.puts("Done!!!")
  end

  defp producer(_q, stop, 10), do: ChanEx.push(stop, "done")

  defp producer(q, stop, n) do
    IO.puts("[producer] send: #{n}")
    ChanEx.push(q, n)
    producer(q, stop, n + 1)
  end

  defp consumer(q) do
    item = ChanEx.pop(q)
    IO.puts("[consumer] receive: #{item}")
    consumer(q)
  end
end
