defmodule ChanExTest do
  use ExUnit.Case
  doctest ChanEx

  setup do
    {:ok, name: :test}
  end

  describe "start_link/1" do
    test "start_link with atom name", %{name: name} do
      start_supervised!({ChanEx, name: name})
    end

    test "start_link with string name" do
      start_supervised!({ChanEx, name: "test1"})
    end

    test "start_link without name" do
      start_supervised!(ChanEx)
    end
  end

  describe "get_chan" do
    test "get_chan without creation", %{name: name} do
      start_supervised!({ChanEx, name: name})
      assert {:ok, _} = ChanEx.get_chan(name, "test")
    end

    test "get existing chan", %{name: name} do
      start_supervised!({ChanEx, name: name})
      {:ok, c1} = ChanEx.get_chan(name, "test")
      {:ok, c2} = ChanEx.get_chan(name, "test")
      assert c1 == c2
    end
  end

  describe "block queue" do
    test "bpush", %{name: name} do
      start_supervised!({ChanEx, name: name})
      {:ok, c} = ChanEx.get_chan(name, "test", capacity: 2)
      assert :ok == ChanEx.bpush(c, 1)
      assert :ok == ChanEx.bpush(c, 2)
      assert :block == GenServer.call(c, {:bpush, 3}, 5000)
    end

    test "push", %{name: name} do
      start_supervised!({ChanEx, name: name})
      {:ok, c} = ChanEx.get_chan(name, "test", capacity: 2)
      assert :ok == ChanEx.push(c, 1)
      assert :ok == ChanEx.push(c, 2)
      assert {:error, _} = ChanEx.push(c, 3)
      assert_raise(RuntimeError, fn -> ChanEx.push!(c, 3) end)
    end

    test "bpop", %{name: name} do
      start_supervised!({ChanEx, name: name})
      {:ok, c} = ChanEx.get_chan(name, "test")
      assert :ok == ChanEx.bpush(c, 1)
      assert 1 == ChanEx.bpop(c)
      assert :block == GenServer.call(c, :bpop, 5000)
    end

    test "pop", %{name: name} do
      start_supervised!({ChanEx, name: name})
      {:ok, c} = ChanEx.get_chan(name, "test")
      assert :ok == ChanEx.push(c, 1)
      assert 1 == ChanEx.pop(c)
      assert {:error, :empty} == ChanEx.pop(c)
      assert_raise(RuntimeError, fn -> ChanEx.pop!(c) end)
    end
  end
end
