defmodule BBS.Component do
  @type assigns :: map

  @callback mount(any, BBS.View.t()) :: {:ok, BBS.View.t()}
  @callback update(any, BBS.View.t()) :: {:ok, BBS.View.t()}
  @callback render(assigns) :: iodata

  defmacro __using__(_) do
    quote do
      @behaviour BBS.Component

      def mount(_arg, view) do
        {:ok, view}
      end

      defoverridable mount: 2
    end
  end
end
