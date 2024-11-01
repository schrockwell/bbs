defmodule BBSTest do
  use ExUnit.Case
  doctest BBS

  test "greets the world" do
    assert BBS.hello() == :world
  end
end
