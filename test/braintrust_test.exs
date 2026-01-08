defmodule BraintrustTest do
  use ExUnit.Case, async: false
  doctest Braintrust

  alias Braintrust.Config

  setup do
    # Store original env var
    original_api_key = System.get_env("BRAINTRUST_API_KEY")

    # Clear env var and process config
    System.delete_env("BRAINTRUST_API_KEY")
    Config.clear()

    on_exit(fn ->
      # Restore original env var
      if original_api_key do
        System.put_env("BRAINTRUST_API_KEY", original_api_key)
      end
    end)

    :ok
  end

  describe "configure/1" do
    test "delegates to Config.configure/1" do
      assert :ok = Braintrust.configure(api_key: "sk-test")
      assert Config.get(:api_key) == "sk-test"
    end
  end
end
