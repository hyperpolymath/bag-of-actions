defmodule BagTest do
  use ExUnit.Case
  doctest Bag

  test "greets the world" do
    assert Bag.hello() == :world
  end
end
