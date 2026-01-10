defmodule Braintrust.LangChainCallbacksTest do
  use ExUnit.Case, async: false
  use Mimic

  alias Braintrust.LangChainCallbacks

  # Mock LangChain structs for testing (since langchain is optional)
  defmodule MockChain do
    defstruct [:llm, :messages, :max_retry_count, :current_failure_count]
  end

  defmodule ChatOpenAI do
    defstruct [:model]
  end

  defmodule MockMessage do
    defstruct [:role, :content, :status, :tool_calls, :tool_results]
  end

  defmodule MockTokenUsage do
    defstruct [:input, :output]
  end

  setup :set_mimic_global

  setup do
    # Clear process dictionary
    Process.delete(:braintrust_langchain_token_usage)

    Application.put_env(:braintrust, :api_key, "test-api-key")
    on_exit(fn -> Application.delete_env(:braintrust, :api_key) end)
    :ok
  end

  describe "handler/1" do
    test "returns a map with expected callback keys" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      assert is_map(handler)
      assert Map.has_key?(handler, :on_llm_token_usage)
      assert Map.has_key?(handler, :on_message_processed)
      assert Map.has_key?(handler, :on_message_processing_error)
      assert Map.has_key?(handler, :on_tool_response_created)
      assert Map.has_key?(handler, :on_retries_exceeded)
    end

    test "raises if project_id is missing" do
      assert_raise KeyError, fn ->
        LangChainCallbacks.handler([])
      end
    end
  end

  describe "on_message_processed callback" do
    test "logs assistant messages to Braintrust" do
      Mimic.expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/project_logs/proj_123/insert"

        body = opts[:json]
        assert length(body.events) == 1

        event = hd(body.events)
        assert event.input["messages"] != nil
        assert event.output == "Hello!"
        assert event.metadata["model"] == "gpt-4"
        assert event.metadata["provider"] == "openai"

        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      handler = LangChainCallbacks.handler(project_id: "proj_123")

      chain = %MockChain{
        llm: %ChatOpenAI{model: "gpt-4"},
        messages: [
          %MockMessage{
            role: :user,
            content: "Hi",
            status: :complete,
            tool_calls: nil,
            tool_results: nil
          }
        ]
      }

      message = %MockMessage{
        role: :assistant,
        content: "Hello!",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      # Call the callback
      handler.on_message_processed.(chain, message)
    end

    test "includes token usage when available" do
      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)

        assert event.metrics["input_tokens"] == 10
        assert event.metrics["output_tokens"] == 20
        assert event.metrics["total_tokens"] == 30

        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      handler = LangChainCallbacks.handler(project_id: "proj_123")

      # Simulate token usage callback first
      usage = %MockTokenUsage{input: 10, output: 20}
      handler.on_llm_token_usage.(nil, usage)

      chain = %MockChain{
        llm: %ChatOpenAI{model: "gpt-4"},
        messages: []
      }

      message = %MockMessage{
        role: :assistant,
        content: "Response",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "does not log non-assistant messages" do
      # No Req.request call expected
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :user,
        content: "Hi",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      # Should return :ok without making HTTP call
      result = handler.on_message_processed.(chain, message)
      assert result == :ok
    end

    test "includes custom metadata and tags" do
      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)

        assert event.metadata["environment"] == "test"
        assert event.metadata["custom_key"] == "custom_value"
        assert event.tags == ["tag1", "tag2"]

        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      handler =
        LangChainCallbacks.handler(
          project_id: "proj_123",
          metadata: %{"environment" => "test", "custom_key" => "custom_value"},
          tags: ["tag1", "tag2"]
        )

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: "Hi",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end
  end

  describe "on_message_processing_error callback" do
    test "logs errors with error tag" do
      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)

        assert event.error == "Message processing error"
        assert event.metadata["error"] == true
        assert "error" in event.tags

        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      handler = LangChainCallbacks.handler(project_id: "proj_123")

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: nil,
        status: :cancelled,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processing_error.(chain, message)
    end
  end

  describe "on_retries_exceeded callback" do
    test "logs retry failure" do
      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)

        assert event.error == "Max retries exceeded"
        assert event.metadata["max_retry_count"] == 3
        assert event.metadata["failure_count"] == 4
        assert "retries_exceeded" in event.tags

        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      handler = LangChainCallbacks.handler(project_id: "proj_123")

      chain = %MockChain{
        llm: %ChatOpenAI{model: "gpt-4"},
        messages: [],
        max_retry_count: 3,
        current_failure_count: 4
      }

      handler.on_retries_exceeded.(chain)
    end
  end

  describe "on_tool_response_created callback" do
    test "logs tool responses" do
      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)

        assert event.input["tool_results"] != nil
        assert event.metadata["span_type"] == "tool"
        assert event.metadata["tool_count"] == 2
        assert "tool" in event.tags

        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      handler = LangChainCallbacks.handler(project_id: "proj_123")

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: "Tool response",
        status: :complete,
        tool_calls: nil,
        tool_results: [
          %{name: "tool1", tool_call_id: "call_1", content: "result1", is_error: false},
          %{name: "tool2", tool_call_id: "call_2", content: "result2", is_error: true}
        ]
      }

      handler.on_tool_response_created.(chain, message)
    end
  end

  describe "content formatting" do
    test "handles binary content" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.output == "text content"
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: "text content",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "handles nil content" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.output == nil
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: nil,
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "handles empty list content" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.output == nil
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: [],
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "handles list with text parts" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.output == "text1"
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: [%{type: :text, content: "text1"}],
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "handles list with multiple text parts" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.output == ["text1", "text2"]
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: [%{type: :text, content: "text1"}, %{type: :text, content: "text2"}],
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "handles binary data content parts" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.output == %{"type" => "image", "content" => "[binary data]"}
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: [%{type: :image}],
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "handles text part with text field instead of content" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.output == "text from text field"
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: [%{type: :text, text: "text from text field"}],
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "handles non-map, non-binary content" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert is_binary(event.output)
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: %{some: "data"},
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end
  end

  describe "metrics building" do
    test "handles nil token usage" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.metrics == %{}
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: "test",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "handles partial token usage (input only)" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      usage = %MockTokenUsage{input: 10, output: nil}
      handler.on_llm_token_usage.(nil, usage)

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.metrics["input_tokens"] == 10
        assert event.metrics["total_tokens"] == 10
        refute Map.has_key?(event.metrics, "output_tokens")
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: "test",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "handles partial token usage (output only)" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      usage = %MockTokenUsage{input: nil, output: 20}
      handler.on_llm_token_usage.(nil, usage)

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.metrics["output_tokens"] == 20
        assert event.metrics["total_tokens"] == 20
        refute Map.has_key?(event.metrics, "input_tokens")
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: "test",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "handles both nil token counts" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      usage = %MockTokenUsage{input: nil, output: nil}
      handler.on_llm_token_usage.(nil, usage)

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.metrics == %{}
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: "test",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end
  end

  describe "chain introspection" do
    test "handles chain with non-string model" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.metadata["model"] == "unknown"
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %ChatOpenAI{model: nil}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: "test",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "handles chain without model field" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.metadata["model"] == "unknown"
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: %{}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: "test",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end

    test "handles error when getting provider name" do
      handler = LangChainCallbacks.handler(project_id: "proj_123")

      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)
        assert event.metadata["provider"] == "unknown"
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      chain = %MockChain{llm: nil, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: "test",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end
  end

  describe "streaming_handler/1" do
    test "includes on_llm_new_delta callback" do
      handler = LangChainCallbacks.streaming_handler(project_id: "proj_123")

      assert Map.has_key?(handler, :on_llm_new_delta)
      assert Map.has_key?(handler, :on_message_processed)
    end

    test "tracks time-to-first-token" do
      Mimic.expect(Req, :request, fn _client, opts ->
        body = opts[:json]
        event = hd(body.events)

        # Streaming metrics should be present
        assert is_integer(event.metrics["time_to_first_token_ms"])
        assert is_integer(event.metrics["streaming_duration_ms"])

        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}}}
      end)

      handler = LangChainCallbacks.streaming_handler(project_id: "proj_123")

      # Simulate delta callbacks
      delta = %{content: "Hello", status: :incomplete}
      handler.on_llm_new_delta.(nil, [delta])

      # Small delay to ensure measurable time
      Process.sleep(10)

      chain = %MockChain{llm: %ChatOpenAI{model: "gpt-4"}, messages: []}

      message = %MockMessage{
        role: :assistant,
        content: "Hello!",
        status: :complete,
        tool_calls: nil,
        tool_results: nil
      }

      handler.on_message_processed.(chain, message)
    end
  end
end
