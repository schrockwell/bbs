defmodule BBS.Format do
  def ansi(ansidata) do
    IO.ANSI.format(ansidata, true)
  end

  def ansi_fragment(ansidata) do
    IO.ANSI.format_fragment(ansidata, true)
  end
end
