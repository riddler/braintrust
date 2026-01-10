defmodule Braintrust.LogTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Braintrust.{Config, Error, Log, Span}

  setup do
    original_api_key = System.get_env("BRAINTRUST_API_KEY")
    System.delete_env("BRAINTRUST_API_KEY")
    Config.clear()
    Config.configure(api_key: "sk-test")

    on_exit(fn ->
      if original_api_key do
        System.put_env("BRAINTRUST_API_KEY", original_api_key)
      end
    end)

    :ok
  end

  describe "insert/3" do
    test "inserts events with raw maps" do
      events = [
        %{
          input: %{messages: [%{role: "user", content: "Hello"}]},
          output: "Hi there!",
          scores: %{quality: 0.9}
        }
      ]

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/project_logs/proj_123/insert"
        assert opts[:json] == %{events: events}
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
      end)

      assert {:ok, result} = Log.insert("proj_123", events)
      assert result["row_ids"] == ["row_1"]
    end

    test "inserts events with Span structs" do
      spans = [
        %Span{
          input: %{messages: [%{role: "user", content: "Hello"}]},
          output: "Hi there!",
          scores: %{quality: 0.9}
        }
      ]

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/project_logs/proj_123/insert"

        # Span should be converted to map with nil values removed
        [event] = opts[:json][:events]
        assert event[:input] == %{messages: [%{role: "user", content: "Hello"}]}
        assert event[:output] == "Hi there!"
        assert event[:scores] == %{quality: 0.9}
        refute Map.has_key?(event, :id)
        refute Map.has_key?(event, :metadata)

        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
      end)

      assert {:ok, result} = Log.insert("proj_123", spans)
      assert result["row_ids"] == ["row_1"]
    end

    test "inserts mixed events (maps and Span structs)" do
      events = [
        %{input: %{q: "map"}, output: "map result"},
        %Span{input: %{q: "span"}, output: "span result"}
      ]

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/project_logs/proj_123/insert"
        [event1, event2] = opts[:json][:events]

        # Map event unchanged
        assert event1 == %{input: %{q: "map"}, output: "map result"}

        # Span converted to map
        assert event2[:input] == %{q: "span"}
        assert event2[:output] == "span result"
        refute Map.has_key?(event2, :id)
        refute Map.has_key?(event2, :metadata)

        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1", "row_2"]}, headers: []}}
      end)

      assert {:ok, result} = Log.insert("proj_123", events)
      assert length(result["row_ids"]) == 2
    end

    test "inserts events with metadata and metrics" do
      events = [
        %{
          input: %{messages: [%{role: "user", content: "test"}]},
          output: "response",
          metadata: %{model: "gpt-4", environment: "production"},
          metrics: %{latency_ms: 250, input_tokens: 50, output_tokens: 25},
          tags: ["production", "chat"]
        }
      ]

      expect(Req, :request, fn _client, opts ->
        [event] = opts[:json][:events]
        assert event[:metadata] == %{model: "gpt-4", environment: "production"}
        assert event[:metrics] == %{latency_ms: 250, input_tokens: 50, output_tokens: 25}
        assert event[:tags] == ["production", "chat"]

        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
      end)

      assert {:ok, _result} = Log.insert("proj_123", events)
    end

    test "inserts multiple events in batch" do
      events =
        Enum.map(1..5, fn i ->
          %{input: %{q: "query_#{i}"}, output: "result_#{i}"}
        end)

      expect(Req, :request, fn _client, opts ->
        assert length(opts[:json][:events]) == 5

        {:ok,
         %Req.Response{
           status: 200,
           body: %{"row_ids" => ["r1", "r2", "r3", "r4", "r5"]},
           headers: []
         }}
      end)

      assert {:ok, result} = Log.insert("proj_123", events)
      assert length(result["row_ids"]) == 5
    end

    test "requires project_id to be a string" do
      assert_raise FunctionClauseError, fn ->
        Log.insert(123, [%{input: %{}, output: "test"}])
      end
    end

    test "requires events to be a list" do
      assert_raise FunctionClauseError, fn ->
        Log.insert("proj_123", %{input: %{}, output: "test"})
      end
    end

    test "returns error on server failure" do
      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Log.insert("proj_123", [%{input: %{}}])
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Project not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Log.insert("invalid_proj", [%{input: %{}}])
    end

    test "returns error on authentication failure" do
      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 401, body: %{"error" => "Unauthorized"}, headers: []}}
      end)

      assert {:error, %Error{type: :authentication}} = Log.insert("proj_123", [%{input: %{}}])
    end

    test "supports api_key option override" do
      events = [%{input: %{q: "test"}, output: "result"}]

      expect(Req, :request, fn client, _opts ->
        assert client.options.auth == {:bearer, "sk-override"}
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
      end)

      assert {:ok, _result} = Log.insert("proj_123", events, api_key: "sk-override")
    end

    test "supports base_url option override" do
      events = [%{input: %{q: "test"}, output: "result"}]

      expect(Req, :request, fn client, _opts ->
        assert client.options.base_url == "https://custom.api.com"
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
      end)

      assert {:ok, _result} = Log.insert("proj_123", events, base_url: "https://custom.api.com")
    end

    test "handles empty events list" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:json] == %{events: []}
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => []}, headers: []}}
      end)

      assert {:ok, result} = Log.insert("proj_123", [])
      assert result["row_ids"] == []
    end

    test "handles events with error field" do
      events = [
        %{
          input: %{messages: [%{role: "user", content: "test"}]},
          error: "LLM API timeout"
        }
      ]

      expect(Req, :request, fn _client, opts ->
        [event] = opts[:json][:events]
        assert event[:error] == "LLM API timeout"
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
      end)

      assert {:ok, _result} = Log.insert("proj_123", events)
    end
  end
end
