defmodule Braintrust.ClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Braintrust.{Client, Config, Error}

  setup do
    # Store original env var
    original_api_key = System.get_env("BRAINTRUST_API_KEY")

    # Clear env var and configure with test key
    System.delete_env("BRAINTRUST_API_KEY")
    Config.clear()
    Config.configure(api_key: "sk-test")

    on_exit(fn ->
      # Restore original env var
      if original_api_key do
        System.put_env("BRAINTRUST_API_KEY", original_api_key)
      end
    end)

    :ok
  end

  describe "new/1" do
    test "creates a Req.Request struct" do
      client = Client.new()
      assert %Req.Request{} = client
    end

    test "uses configured base_url" do
      client = Client.new(base_url: "https://custom.api.com")
      assert client.options.base_url == "https://custom.api.com"
    end

    test "raises when no api_key configured" do
      Config.clear()

      assert_raise ArgumentError, ~r/API key not configured/, fn ->
        Client.new()
      end
    end
  end

  describe "get/3" do
    test "returns decoded JSON on success" do
      client = Client.new()
      response_body = %{"id" => "proj_123", "name" => "test"}

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :get
        assert opts[:url] == "/v1/project"
        {:ok, %Req.Response{status: 200, body: response_body, headers: []}}
      end)

      assert {:ok, ^response_body} = Client.get(client, "/v1/project")
    end

    test "returns error on 404" do
      client = Client.new()
      error_body = %{"error" => %{"message" => "Project not found"}}

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 404, body: error_body, headers: []}}
      end)

      assert {:error, %Error{type: :not_found, message: "Project not found"}} =
               Client.get(client, "/v1/project/invalid")
    end

    test "returns error with retry_after on 429" do
      client = Client.new()
      error_body = %{"error" => %{"message" => "Rate limit exceeded"}}

      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 429,
           body: error_body,
           headers: [{"retry-after", "5"}]
         }}
      end)

      assert {:error, %Error{type: :rate_limit, retry_after: 5000}} =
               Client.get(client, "/v1/project")
    end

    test "returns timeout error" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:error, %Error{type: :timeout}} = Client.get(client, "/v1/project")
    end

    test "returns connection error" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:error, %Req.TransportError{reason: :econnrefused}}
      end)

      assert {:error, %Error{type: :connection}} = Client.get(client, "/v1/project")
    end
  end

  describe "post/4" do
    test "sends JSON body and returns decoded response" do
      client = Client.new()
      request_body = %{name: "new-project"}
      response_body = %{"id" => "proj_123", "name" => "new-project"}

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/project"
        assert opts[:json] == request_body
        {:ok, %Req.Response{status: 201, body: response_body, headers: []}}
      end)

      assert {:ok, ^response_body} = Client.post(client, "/v1/project", request_body)
    end

    test "returns error on 400 with error message" do
      client = Client.new()
      error_body = %{"error" => %{"message" => "Name is required", "code" => "validation_error"}}

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 400, body: error_body, headers: []}}
      end)

      assert {:error,
              %Error{
                type: :bad_request,
                message: "Name is required",
                code: "validation_error",
                status: 400
              }} = Client.post(client, "/v1/project", %{})
    end
  end

  describe "patch/4" do
    test "sends JSON body for partial update" do
      client = Client.new()
      request_body = %{name: "updated-name"}
      response_body = %{"id" => "proj_123", "name" => "updated-name"}

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json] == request_body
        {:ok, %Req.Response{status: 200, body: response_body, headers: []}}
      end)

      assert {:ok, ^response_body} = Client.patch(client, "/v1/project/proj_123", request_body)
    end
  end

  describe "delete/3" do
    test "returns success on 200" do
      client = Client.new()
      response_body = %{"id" => "proj_123", "deleted" => true}

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete
        {:ok, %Req.Response{status: 200, body: response_body, headers: []}}
      end)

      assert {:ok, ^response_body} = Client.delete(client, "/v1/project/proj_123")
    end

    test "returns error on 403" do
      client = Client.new()
      error_body = %{"error" => %{"message" => "Permission denied"}}

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 403, body: error_body, headers: []}}
      end)

      assert {:error, %Error{type: :permission_denied}} =
               Client.delete(client, "/v1/project/proj_123")
    end
  end
end
