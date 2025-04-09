defmodule TaliskerTest do
  use ExUnit.Case
  doctest Talisker

  test "greets the world" do
    assert Talisker.hello() == :world
  end
end
