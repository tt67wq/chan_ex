defmodule ChanEx do
  @moduledoc false

  use Supervisor

  @opt_schema [
    name: [
      type: :atom,
      default: __MODULE__,
      doc: "name of chan manager"
    ]
  ]

  @default_chan_capacity 256

  def start_link(opts) do
    opts = NimbleOptions.validate!(opts, @opt_schema)
    name = opts[:name]

    cfg = [
      registry_name: registry_name(name),
      dynamic_supervisor_name: dynamic_supervisor_name(name)
    ]

    Supervisor.start_link(__MODULE__, cfg, name: opts[:name])
  end

  defp registry_name(name), do: :"#{name}.Registry"
  defp dynamic_supervisor_name(name), do: :"#{name}.DynamicSupervisor"

  def init(cfg) do
    children = [
      {Registry, [keys: :unique, name: cfg[:registry_name]]},
      {DynamicSupervisor, name: cfg[:dynamic_supervisor_name], strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  @type chan_name_t :: String.t() | atom()

  @spec new_chan(atom, chan_name_t(), non_neg_integer) ::
          {:error, any} | {:ok, pid}
  def new_chan(domain, name, capacity \\ @default_chan_capacity) do
    DynamicSupervisor.start_child(
      dynamic_supervisor_name(domain),
      {ChanEx.BlockChan, capacity: capacity, name: chan_name(domain, name)}
    )
  end

  @spec get_chan(atom, atom | binary, any) :: {:error, any} | {:ok, pid}
  def get_chan(domain, name, capacity \\ @default_chan_capacity) do
    case lookup_chan(domain, name) do
      nil -> new_chan(domain, name, capacity)
      {:ok, pid} -> {:ok, pid}
    end
  end

  defp lookup_chan(domain, name) do
    domain
    |> registry_name()
    |> Registry.lookup(name)
    |> case do
      [] -> nil
      [{pid, _}] -> {:ok, pid}
    end
  end

  defp chan_name(domain, name),
    do: {:via, Registry, {registry_name(domain), name}}

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
