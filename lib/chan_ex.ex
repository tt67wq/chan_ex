defmodule ChanEx do
  @external_resource "README.md"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  use Supervisor

  @opt_schema [
    name: [
      type: {:or, [:atom, :string]},
      default: __MODULE__,
      doc: "name of chan manager"
    ]
  ]

  @default_chan_capacity 256

  @spec start_link(keyword) :: :ignore | {:error, any} | {:ok, pid}
  @doc """
  start a new channel manager

  ## Options
  #{NimbleOptions.docs(@opt_schema)}
  """
  def start_link(opts) do
    opts = NimbleOptions.validate!(opts, @opt_schema)
    name = opts[:name]

    cfg = [
      registry_name: registry_name(name),
      dynamic_supervisor_name: dynamic_supervisor_name(name)
    ]

    Supervisor.start_link(__MODULE__, cfg, name: supervisor_name(name))
  end

  defp registry_name(name), do: :"#{name}.Registry"
  defp dynamic_supervisor_name(name), do: :"#{name}.DynamicSupervisor"
  defp supervisor_name(name), do: :"#{name}.Supervisor"

  def init(cfg) do
    children = [
      {Registry, [keys: :unique, name: cfg[:registry_name]]},
      {DynamicSupervisor, name: cfg[:dynamic_supervisor_name], strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @type chan_name_t :: String.t() | atom()

  @spec new_chan(atom(), chan_name_t(), non_neg_integer) ::
          {:error, any} | {:ok, pid}
  def new_chan(manager_name, name, capacity \\ @default_chan_capacity) do
    DynamicSupervisor.start_child(
      dynamic_supervisor_name(manager_name),
      {ChanEx.BlockChan, capacity: capacity, name: chan_name(manager_name, name)}
    )
  end

  @spec get_chan(atom, chan_name_t(), any) :: {:error, any} | {:ok, pid}
  def get_chan(manager_name, name, capacity \\ @default_chan_capacity) do
    case lookup_chan(manager_name, name) do
      nil -> new_chan(manager_name, name, capacity)
      {:ok, pid} -> {:ok, pid}
    end
  end

  defp lookup_chan(manager_name, name) do
    manager_name
    |> registry_name()
    |> Registry.lookup(name)
    |> case do
      [] -> nil
      [{pid, _}] -> {:ok, pid}
    end
  end

  defp chan_name(manager_name, name),
    do: {:via, Registry, {registry_name(manager_name), name}}

  defdelegate bpush(pid, item, timeout \\ 5000), to: ChanEx.BlockChan
  defdelegate push(pid, item, timeout \\ 5000), to: ChanEx.BlockChan
  defdelegate push!(pid, item, timeout \\ 5000), to: ChanEx.BlockChan
  defdelegate bpop(pid, timeout \\ 5000), to: ChanEx.BlockChan
  defdelegate pop(pid, timeout \\ 5000), to: ChanEx.BlockChan
  defdelegate pop!(pid, timeout \\ 5000), to: ChanEx.BlockChan
  defdelegate empty?(pid), to: ChanEx.BlockChan
  defdelegate size(pid), to: ChanEx.BlockChan
  defdelegate close(pid), to: ChanEx.BlockChan
end
