defmodule BBS.View do
  defstruct assigns: %{__changed__: false},
            socket: nil,
            private: %{},
            id: nil,
            connection_pid: nil

  alias BBS.Connection
  alias BBS.View.Prompt

  @type t :: %__MODULE__{
          assigns: map,
          socket: :gen_tcp.socket()
        }

  @callback mount(arg :: any, session :: map, view :: t) :: {:ok, t}
  @callback handle_data(String.t() | atom, view :: t) :: {:noreply, t}
  @callback handle_prompt(term, String.t(), view :: t) :: {:noreply, t}
  @callback handle_info(msg :: :timeout | term, state :: term) ::
              {:noreply, new_state}
              | {:noreply, new_state, timeout | :hibernate | {:continue, term}}
              | {:stop, reason :: term, new_state}
            when new_state: term

  @optional_callbacks [
    handle_data: 2,
    handle_prompt: 3,
    handle_info: 2
  ]

  def print(view, iodata) do
    :ok = :gen_tcp.send(view.socket, iodata)
    view
  end

  def println(view, iodata \\ "") do
    print(view, [iodata, ?\r, ?\n])
  end

  def clear(view) do
    print(view, IO.ANSI.reset() <> IO.ANSI.clear())
  end

  def clear_line(view) do
    print(view, "\r" <> IO.ANSI.clear_line())
  end

  def prompt(view, name, opts \\ []) do
    # if view.prompt do
    #   raise "can't start prompt #{inspect(name)}, prompt #{inspect(view.prompt.name)} is already active"
    # end

    prompt = Prompt.new(name, opts)

    print(view, prompt.format <> Prompt.placeholder(prompt) <> IO.ANSI.reset())

    put_private(view, :prompt, prompt)
  end

  def cancel_prompt(view) do
    delete_private(view, :prompt)
  end

  def assign(view, key, value) do
    assign(view, %{key => value})
  end

  def assign(view, assigns) do
    next_assigns = Map.merge(view.assigns, Map.new(assigns))
    changed = next_assigns != view.assigns
    next_assigns = Map.put(next_assigns, :__changed__, changed)
    %{view | assigns: next_assigns}
  end

  def put_session(view, key, value) do
    Connection.put_session(view.connection_pid, key, value)
    view
  end

  def delete_session(view, key) do
    Connection.delete_session(view.connection_pid, key)
    view
  end

  def navigate(view, view_module, mount_arg \\ nil) do
    Connection.navigate(view.connection_pid, view_module, mount_arg)
    view
  end

  def disconnect(view) do
    Connection.close(view.connection_pid)
    view
  end

  def component(view, id, module, position, mount_arg \\ nil) do
    info = %{
      id: id,
      module: module,
      mount_arg: mount_arg,
      position: position
    }

    send(self(), {BBS, :component, info})
    view
  end

  def send_update(pid \\ self(), id, msg) do
    send(pid, {BBS, :update, id, msg})
  end

  def send_update_after(pid \\ self(), id, msg, milliseconds) do
    Process.send_after(pid, {BBS, :update, id, msg}, milliseconds)
  end

  def put_private(view, key, value) do
    %{view | private: Map.put(view.private, key, value)}
  end

  def delete_private(view, key) do
    %{view | private: Map.delete(view.private, key)}
  end
end
