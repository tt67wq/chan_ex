defmodule ChanExTest do
  use ExUnit.Case, async: true
  doctest ChanEx

  setup do
    {:ok, name: :test}
  end

  describe "start_link/1" do
    test "start_link with name", %{name: name} do
      start_supervised!({ChanEx, name: name})
    end

    test "start_link without name" do
      start_supervised!(ChanEx)
    end
  end

  describe "new_chan" do
    test "new_chan with string name", %{name: name} do
      start_supervised!({ChanEx, name: name})
      assert {:ok, _} = ChanEx.new_chan(name, "test", 120)
    end

    test "new_chan with atom name", %{name: name} do
      start_supervised!({ChanEx, name: name})
      assert {:ok, _} = ChanEx.new_chan(name, :test_chan, 120)
    end
  end

  describe "get_chan" do
    test "get_chan without creation", %{name: name} do
      start_supervised!({ChanEx, name: name})
      assert {:ok, _} = ChanEx.get_chan(name, "test", 120)
    end

    test "get existing chan", %{name: name} do
      start_supervised!({ChanEx, name: name})
      {:ok, c1} = ChanEx.new_chan(name, "test", 120)
      {:ok, c2} = ChanEx.get_chan(name, "test", 120)
      assert c1 == c2
    end
  end

  describe "block queue" do
    test "bpush", %{name: name} do
      start_supervised!({ChanEx, name: name})
      {:ok, c} = ChanEx.new_chan(name, "test", 2)
      assert :ok == ChanEx.bpush(c, 1)
      assert :ok == ChanEx.bpush(c, 2)
      assert :block == GenServer.call(c, {:bpush, 3}, 5000)
    end

    test "bpop", %{name: name} do
      start_supervised!({ChanEx, name: name})
      {:ok, c} = ChanEx.new_chan(name, "test", 2)
      assert :ok == ChanEx.bpush(c, 1)
      assert 1 == ChanEx.bpop(c)
      assert :block == GenServer.call(c, :bpop, 5000)
    end
  end
end
