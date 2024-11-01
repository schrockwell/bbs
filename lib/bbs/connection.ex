defmodule BBS.Connection do
  use GenServer, restart: :transient

  require Logger

  alias BBS.ViewServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def navigate(pid, view_module, mount_arg) do
    GenServer.cast(pid, {:navigate, view_module, mount_arg})
  end

  def close(pid) do
    GenServer.cast(pid, :close)
  end

  def put_session(pid, key, value) do
    GenServer.cast(pid, {:put_session, key, value})
  end

  def delete_session(pid, key) do
    GenServer.cast(pid, {:delete_session, key})
  end

  def put_view_pid(pid, view_pid) do
    GenServer.cast(pid, {:put_view_pid, view_pid})
  end

  def send(pid, iodata) do
    GenServer.cast(pid, {:send, iodata})
  end

  @impl true
  def init(opts) do
    client_socket = Keyword.fetch!(opts, :socket)
    initial_view = Keyword.fetch!(opts, :initial_view)

    ip =
      case :inet.peername(client_socket) do
        {:ok, {ip, _}} -> ip |> :inet.ntoa() |> to_string()
        {:error, _reason} -> nil
      end

    Logger.info("Accepted connection from #{ip || "<unknown>"}")

    navigate(self(), initial_view, :initial)

    {:ok,
     %{
       client_ip: ip,
       session: %{},
       socket: client_socket,
       lexer: %Telnex.Lexer{},
       echo?: false,
       view_pid: nil,
       buffer: "",
       mode: %BBS.Mode{}
     }}
  end

  @impl true
  def handle_info({:tcp, _socket, data}, state) do
    {new_data, lexer} = Telnex.Lexer.put(state.lexer, data)
    # Logger.info("Received data: #{inspect(new_data)}")

    # TODO: Make the new_data return string chunks instead of individual characters

    {new_data, new_buffer} =
      Enum.reduce(new_data, {[], state.buffer}, fn
        item, {result, buffer} when is_binary(item) ->
          {decoded, rest} = Antsy.decode(buffer <> item)
          {result ++ decoded, rest}

        data, {result, buffer} ->
          {result ++ [data], buffer}
      end)

    state = Enum.reduce(new_data, state, &handle_telnet_token/2)

    # if state.echo? do
    #   :ok = :gen_tcp.send(state.socket, data)
    # end

    {:noreply, %{state | lexer: lexer, buffer: new_buffer}}
  end

  def handle_info({:tcp_closed, _socket}, state) do
    Logger.info("Connection closed from #{state.client_ip}")

    {:stop, :normal, state}
  end

  @impl true
  def handle_cast({:navigate, view_module, mount_arg}, state) do
    if state.view_pid do
      GenServer.stop(state.view_pid, :normal)
    end

    {:ok, view_pid} =
      BBS.Supervisor.start_view(
        connection_pid: self(),
        module: view_module,
        mount_arg: mount_arg,
        socket: state.socket,
        session: state.session
      )

    {:noreply, %{state | view_pid: view_pid}}
  end

  def handle_cast({:put_session, key, value}, state) do
    {:noreply, %{state | session: Map.put(state.session, key, value)}}
  end

  def handle_cast({:delete_session, key}, state) do
    {:noreply, %{state | session: Map.delete(state.session, key)}}
  end

  def handle_cast({:put_view_pid, view_pid}, state) do
    {:noreply, %{state | view_pid: view_pid}}
  end

  def handle_cast(:close, state) do
    Logger.info("Closing connection from #{state.client_ip}")
    :ok = :gen_tcp.close(state.socket)
    {:stop, :normal, state}
  end

  def handle_cast({:send, iodata}, state) do
    :ok = :gen_tcp.send(state.socket, iodata)
    {:noreply, state}
  end

  # defp handle_telnet_token({verb, _value} = option, state)
  #      when verb in [:will, :wont, :do, :dont] do
  #   %{state | client_options: [option | state.client_options]}
  # end

  @echo 1
  @iac 255
  @will 251
  @wont 252
  # @doo 253
  # @dont 254

  defp handle_telnet_token({:do, @echo}, state) do
    :gen_tcp.send(state.socket, [@iac, @will, @echo])
    %{state | echo?: true}
  end

  defp handle_telnet_token({:dont, @echo}, state) do
    :gen_tcp.send(state.socket, [@iac, @wont, @echo])
    %{state | echo?: false}
  end

  defp handle_telnet_token(data, state) do
    ViewServer.handle_data(state.view_pid, data)
    state
  end
end
