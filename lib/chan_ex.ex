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

  def start_link(opts) do
    opts = NimbleOptions.validate!(opts, @opt_schema)
    name = opts[:name]

    cfg = [
      registry_name: registry_name(name),
      dynamic_supervisor_name: dynamic_supervisor_name(name),
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
end
