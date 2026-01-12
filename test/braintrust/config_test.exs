defmodule Braintrust.ConfigTest do
  use ExUnit.Case, async: false
  doctest Braintrust.Config

  alias Braintrust.Config

  setup do
    # Store original env vars
    original_api_key = System.get_env("BRAINTRUST_API_KEY")
    original_api_url = System.get_env("BRAINTRUST_API_URL")

    # Clean up any process-level config
    Config.clear()
    # Clean up any app-level config
    Application.delete_env(:braintrust, :api_key)
    Application.delete_env(:braintrust, :base_url)
    Application.delete_env(:braintrust, :timeout)
    Application.delete_env(:braintrust, :max_retries)
    # Clear env vars for tests
    System.delete_env("BRAINTRUST_API_KEY")
    System.delete_env("BRAINTRUST_API_URL")

    on_exit(fn ->
      # Restore original env vars
      if original_api_key do
        System.put_env("BRAINTRUST_API_KEY", original_api_key)
      end

      if original_api_url do
        System.put_env("BRAINTRUST_API_URL", original_api_url)
      end
    end)

    :ok
  end

  describe "get/2" do
    test "returns default base_url" do
      assert Config.get(:base_url) == "https://api.braintrust.dev"
    end

    test "returns default timeout" do
      assert Config.get(:timeout) == 60_000
    end

    test "returns default max_retries" do
      assert Config.get(:max_retries) == 2
    end

    test "runtime opts take precedence" do
      Config.configure(base_url: "https://process.local")
      Application.put_env(:braintrust, :base_url, "https://app.local")

      assert Config.get(:base_url, base_url: "https://opts.local") == "https://opts.local"
    end

    test "process config takes precedence over app config" do
      Config.configure(base_url: "https://process.local")
      Application.put_env(:braintrust, :base_url, "https://app.local")

      assert Config.get(:base_url) == "https://process.local"
    end

    test "app config takes precedence over defaults" do
      Application.put_env(:braintrust, :timeout, 15_000)

      assert Config.get(:timeout) == 15_000
    end

    test "env var takes precedence over default for base_url" do
      System.put_env("BRAINTRUST_API_URL", "https://self-hosted.example.com")

      assert Config.get(:base_url) == "https://self-hosted.example.com"
    end

    test "app config takes precedence over env var for base_url" do
      System.put_env("BRAINTRUST_API_URL", "https://env.example.com")
      Application.put_env(:braintrust, :base_url, "https://app.example.com")

      assert Config.get(:base_url) == "https://app.example.com"
    end
  end

  describe "api_key!/1" do
    test "returns api_key from opts" do
      assert Config.api_key!(api_key: "sk-opts") == "sk-opts"
    end

    test "returns api_key from process config" do
      Config.configure(api_key: "sk-process")
      assert Config.api_key!() == "sk-process"
    end

    test "returns api_key from app config" do
      Application.put_env(:braintrust, :api_key, "sk-app")
      assert Config.api_key!() == "sk-app"
    end

    test "raises when no api_key configured" do
      assert_raise ArgumentError, ~r/API key not configured/, fn ->
        Config.api_key!()
      end
    end
  end

  describe "configure/1" do
    test "sets process-level config" do
      Config.configure(
        api_key: "sk-test",
        base_url: "https://custom.local",
        timeout: 5000,
        max_retries: 5
      )

      assert Config.get(:api_key) == "sk-test"
      assert Config.get(:base_url) == "https://custom.local"
      assert Config.get(:timeout) == 5000
      assert Config.get(:max_retries) == 5
    end

    test "only sets provided options" do
      Config.configure(api_key: "sk-test")

      assert Config.get(:api_key) == "sk-test"
      # Others should still be defaults
      assert Config.get(:base_url) == "https://api.braintrust.dev"
    end
  end

  describe "clear/0" do
    test "clears process-level config" do
      Config.configure(api_key: "sk-test", timeout: 5000)
      Config.clear()

      assert Config.get(:api_key) == nil
      assert Config.get(:timeout) == 60_000
    end
  end

  describe "valid_api_key?/1" do
    test "returns true for user API keys" do
      assert Config.valid_api_key?("sk-abc123")
      assert Config.valid_api_key?("sk-very-long-key-here")
    end

    test "returns true for service tokens" do
      assert Config.valid_api_key?("bt-st-abc123")
      assert Config.valid_api_key?("bt-st-very-long-token")
    end

    test "returns false for invalid keys" do
      refute Config.valid_api_key?(nil)
      refute Config.valid_api_key?("")
      refute Config.valid_api_key?("invalid")
      refute Config.valid_api_key?("api-key")
    end
  end
end
