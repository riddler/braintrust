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
           headers: %{"retry-after" => ["5"]}
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

    test "handles unexpected exceptions" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:error, %RuntimeError{message: "Something went wrong"}}
      end)

      assert {:error,
              %Error{type: :connection, message: "Unexpected error: Something went wrong"}} =
               Client.get(client, "/v1/project")
    end

    test "handles server errors (500)" do
      client = Client.new()
      error_body = %{"error" => "Internal server error"}

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: error_body, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Client.get(client, "/v1/project")
    end

    test "handles string error bodies" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 400, body: "Bad request", headers: %{}}}
      end)

      assert {:error, %Error{type: :bad_request, message: "Bad request"}} =
               Client.get(client, "/v1/project")
    end

    test "handles simple error message format" do
      client = Client.new()
      error_body = %{"message" => "Simple error"}

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 400, body: error_body, headers: %{}}}
      end)

      assert {:error, %Error{type: :bad_request, message: "Simple error"}} =
               Client.get(client, "/v1/project")
    end

    test "handles error string format" do
      client = Client.new()
      error_body = %{"error" => "Error string"}

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 400, body: error_body, headers: %{}}}
      end)

      assert {:error, %Error{type: :bad_request, message: "Error string"}} =
               Client.get(client, "/v1/project")
    end

    test "handles non-integer retry-after header" do
      client = Client.new()
      error_body = %{"error" => %{"message" => "Rate limited"}}

      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 429,
           body: error_body,
           headers: %{"retry-after" => ["invalid"]}
         }}
      end)

      assert {:error, %Error{type: :rate_limit, retry_after: nil}} =
               Client.get(client, "/v1/project")
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

  describe "get_stream/3" do
    test "returns a stream of items" do
      client = Client.new()

      # First call returns items, second call returns empty to signal end
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        assert opts[:method] == :get
        assert opts[:url] == "/v1/project"

        case page do
          0 ->
            assert opts[:params][:limit] == 50

            {:ok,
             %Req.Response{
               status: 200,
               body: %{"objects" => [%{"id" => "1"}, %{"id" => "2"}]},
               headers: []
             }}

          _subsequent ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{"objects" => []},
               headers: []
             }}
        end
      end)

      result = Client.get_stream(client, "/v1/project", limit: 50) |> Enum.to_list()
      assert result == [%{"id" => "1"}, %{"id" => "2"}]

      Agent.stop(agent)
    end
  end

  describe "get_all/3" do
    test "returns all items as a list" do
      client = Client.new()

      # First call returns items, second call returns empty to signal end
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      stub(Req, :request, fn _client, _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{"objects" => [%{"id" => "1"}]},
               headers: []
             }}

          _subsequent ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{"objects" => []},
               headers: []
             }}
        end
      end)

      assert {:ok, [%{"id" => "1"}]} = Client.get_all(client, "/v1/project")

      Agent.stop(agent)
    end

    test "returns error on API failure" do
      client = Client.new()

      stub(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Client.get_all(client, "/v1/project")
    end
  end

  describe "error handling edge cases" do
    test "handles empty error body" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 400, body: %{}, headers: %{}}}
      end)

      assert {:error, %Error{type: :bad_request, message: "Request failed"}} =
               Client.get(client, "/v1/project")
    end

    test "handles non-map, non-string error body" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 400, body: nil, headers: %{}}}
      end)

      assert {:error, %Error{type: :bad_request, message: "Request failed"}} =
               Client.get(client, "/v1/project")
    end

    test "extracts error code from nested error object" do
      client = Client.new()
      error_body = %{"error" => %{"message" => "Error", "code" => "test_code"}}

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 400, body: error_body, headers: %{}}}
      end)

      assert {:error, %Error{code: "test_code"}} = Client.get(client, "/v1/project")
    end

    test "extracts error code from top-level" do
      client = Client.new()
      error_body = %{"message" => "Error", "code" => "top_level_code"}

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 400, body: error_body, headers: %{}}}
      end)

      assert {:error, %Error{code: "top_level_code"}} = Client.get(client, "/v1/project")
    end

    test "handles retry-after header with non-list value" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 429,
           body: %{"error" => "Rate limited"},
           headers: %{"retry-after" => "5"}
         }}
      end)

      assert {:error, %Error{type: :rate_limit, retry_after: nil}} =
               Client.get(client, "/v1/project")
    end

    test "handles retry-after header with empty list" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 429,
           body: %{"error" => "Rate limited"},
           headers: %{"retry-after" => []}
         }}
      end)

      assert {:error, %Error{type: :rate_limit, retry_after: nil}} =
               Client.get(client, "/v1/project")
    end

    test "handles non-map headers" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 429, body: %{"error" => "Rate limited"}, headers: []}}
      end)

      assert {:error, %Error{type: :rate_limit, retry_after: nil}} =
               Client.get(client, "/v1/project")
    end
  end

  describe "status code handling" do
    test "handles 408 Request Timeout" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 408, body: %{"error" => "Timeout"}, headers: %{}}}
      end)

      # 408 is not explicitly mapped, so falls through to :bad_request
      assert {:error, %Error{type: :bad_request, status: 408}} = Client.get(client, "/v1/project")
    end

    test "handles 409 Conflict" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 409, body: %{"error" => "Conflict"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :conflict}} = Client.get(client, "/v1/project")
    end

    test "handles 401 Unauthorized" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 401, body: %{"error" => "Unauthorized"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :authentication}} = Client.get(client, "/v1/project")
    end

    test "handles 422 Unprocessable Entity" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 422,
           body: %{"error" => "Validation failed"},
           headers: %{}
         }}
      end)

      assert {:error, %Error{type: :unprocessable_entity}} = Client.get(client, "/v1/project")
    end
  end
end
