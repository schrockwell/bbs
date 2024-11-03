defmodule BBS.ViewServer do
  use GenServer, restart: :transient

  alias BBS.Connection
  alias BBS.View
  alias BBS.View.Prompt

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def handle_data(pid, data) do
    GenServer.cast(pid, {:handle_data, data})
  end

  @impl GenServer
  def init(opts) do
    connection_pid = Keyword.fetch!(opts, :connection_pid)
    socket = Keyword.fetch!(opts, :socket)
    module = Keyword.fetch!(opts, :module)
    mount_arg = Keyword.get(opts, :mount_arg)
    session = Keyword.fetch!(opts, :session)

    view = %BBS.View{
      connection_pid: connection_pid,
      socket: socket
    }

    monitor_ref = Process.monitor(connection_pid)

    Connection.put_view_pid(connection_pid, self())

    {:ok, new_view} = module.mount(mount_arg, session, view)

    {:ok,
     %{
       connection_pid: connection_pid,
       components: %{},
       module: module,
       monitor_ref: monitor_ref,
       socket: socket,
       view: new_view
     }}
  end

  @impl GenServer
  def handle_cast(
        {:handle_data, data},
        %{view: %{private: %{prompt: %Prompt{} = prompt}} = view} = state
      ) do
    case Prompt.put(prompt, data) do
      {:cont, prompt, echo} ->
        Connection.send(state.connection_pid, echo)
        {:noreply, %{state | view: View.put_private(view, :prompt, prompt)}}

      {:halt, value} ->
        view = View.cancel_prompt(view)

        prompt.name
        |> state.module.handle_prompt(value, view)
        |> handle_view_callback(state)
    end
  end

  def handle_cast({:handle_data, data}, state) do
    if function_exported?(state.module, :handle_data, 2) do
      data
      |> state.module.handle_data(state.view)
      |> handle_view_callback(state)
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{monitor_ref: ref} = state) do
    {:stop, :normal, state}
  end

  def handle_info({BBS, :update, id, msg}, state) do
    component =
      Map.get(state.components, id) ||
        raise "Component with id #{id} does not exist in this view"

    {:ok, next_view} = component.module.update(msg, component.view)

    needs_render = next_view.assigns.__changed__
    next_assigns = Map.put(next_view.assigns, :__changed__, false)
    next_view = %{next_view | assigns: next_assigns}
    next_component = %{component | view: next_view}
    next_components = Map.put(state.components, id, next_component)
    next_state = %{state | components: next_components}

    if needs_render do
      render_component(next_state, next_component)
    end

    {:noreply, next_state}
  end

  def handle_info({BBS, :component, info}, state) do
    if state.components[info.id] do
      raise "Component with id #{info.id} already exists in this view"
    end

    initial_view = %BBS.View{
      connection_pid: state.connection_pid,
      id: info.id,
      socket: state.socket
    }

    {:ok, view} = info.module.mount(info.mount_arg, initial_view)

    component = %{
      id: info.id,
      module: info.module,
      position: info.position,
      view: view
    }

    render_component(state, component)

    next_components = Map.put(state.components, component.id, component)
    state = %{state | components: next_components}

    {:noreply, state}
  end

  def handle_info(msg, state) do
    msg
    |> state.module.handle_info(state.view)
    |> handle_view_callback(state)
  end

  defp handle_view_callback({:noreply, %View{} = view}, state) do
    {:noreply, %{state | view: view}}
  end

  defp handle_view_callback({:noreply, %View{} = view, timeout}, state) do
    {:noreply, %{state | view: view}, timeout}
  end

  defp handle_view_callback({:stop, reason, %View{} = view}, state) do
    {:stop, reason, %{state | view: view}}
  end

  defp render_component(state, component) do
    {line, col} = component.position

    # save cursor position and move to component position
    Connection.send(state.connection_pid, ["\e[s", IO.ANSI.cursor(line, col)])

    # render component
    component.module.render(component.view)

    # restore cursor position
    Connection.send(state.connection_pid, "\e[u")

    state
  end
end
