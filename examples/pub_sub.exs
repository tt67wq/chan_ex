# Usage: mix run examples/pub_sub.exs
#
# Hit Ctrl+C twice to stop it.

defmodule Pub do

  def pub(chan, idx) do
    msg = "[#{idx}]"
    IO.puts("pub msg #{msg}")
    ChanEx.bpush(chan, msg)
    Process.sleep(1000)
    pub(chan, idx+1)
  end
end

defmodule Sub do
  def sub(name, chan) do
    msg = ChanEx.bpop(chan)
    IO.puts("#{name}: recv msg #{msg}")
    sub(name, chan)
  end
end


{:ok, _} = ChanEx.start_link(name: :pubsub)
{:ok, chan} = ChanEx.get_chan(:pubsub, "default")

Task.start_link(fn -> Pub.pub(chan, 1) end)
Task.start_link(fn -> Sub.sub("suber1", chan) end)
Task.start_link(fn -> Sub.sub("suber2", chan) end)
Process.sleep(:infinity)
