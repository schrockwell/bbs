defmodule BBS.Supervisor do
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_connection(opts) do
    child_spec = {BBS.Connection, opts}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def start_view(opts) do
    child_spec = {BBS.ViewServer, opts}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end
