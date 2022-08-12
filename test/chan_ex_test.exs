defmodule ChanExTest do
  use ExUnit.Case
  doctest ChanEx

  test "greets the world" do
    assert ChanEx.hello() == :world
  end
end
