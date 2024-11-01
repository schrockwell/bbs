defmodule BBS.Endpoint do
  use GenServer

  require Logger

  @port 23

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    {:ok, socket} =
      :gen_tcp.listen(@port, [:binary, active: true, reuseaddr: true])

    initial_view = Keyword.fetch!(opts, :initial_view)

    Logger.info("Listening on port #{@port}")

    {:ok, %{socket: socket, initial_view: initial_view}, {:continue, :accept_connections}}
  end

  def handle_continue(:accept_connections, state) do
    accept_loop(state)
  end

  # Loop to accept connections and spawn a new process for each connection
  defp accept_loop(state) do
    {:ok, client_socket} = :gen_tcp.accept(state.socket)

    {:ok, pid} =
      BBS.Supervisor.start_connection(
        socket: client_socket,
        initial_view: state.initial_view
      )

    :ok = :gen_tcp.controlling_process(client_socket, pid)

    accept_loop(state)
  end
end
