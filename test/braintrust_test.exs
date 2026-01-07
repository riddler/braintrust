defmodule BraintrustTest do
  use ExUnit.Case
  doctest Braintrust

  test "greets the world" do
    assert Braintrust.hello() == :world
  end
end
