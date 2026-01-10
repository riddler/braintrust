# LangChain Integration Implementation Plan

## Overview

Implement LangChain Elixir integration for Braintrust observability. This provides a callback handler that automatically logs LLM interactions to Braintrust when used with LangChain's `LLMChain`.

**Key insight**: Since LLM calls typically take 500ms-5s+, synchronous logging adds negligible overhead. No async batching complexity needed.

## Current State Analysis

### Existing Braintrust SDK

The SDK already has the core logging infrastructure:

- **`Braintrust.Log.insert/3`** at `lib/braintrust/log.ex:136` - Accepts project_id, events list, and opts
- **`Braintrust.Span`** struct at `lib/braintrust/span.ex:105` - Data structure with input, output, scores, metadata, metrics, tags, error fields
- **`Braintrust.Client`** at `lib/braintrust/client.ex` - HTTP client with retry logic

### LangChain Callback System

LangChain provides callbacks via `LangChain.Chains.ChainCallbacks`:

| Callback | Signature | When Fired |
|----------|-----------|------------|
| `on_llm_new_message` | `(LLMChain.t(), Message.t() -> any())` | Complete non-streamed message received |
| `on_llm_token_usage` | `(LLMChain.t(), TokenUsage.t() -> any())` | Token usage data reported |
| `on_llm_new_delta` | `(LLMChain.t(), [MessageDelta.t()] -> any())` | Streaming tokens received (list of deltas) |
| `on_message_processed` | `(LLMChain.t(), Message.t() -> any())` | Chain finished processing message |
| `on_message_processing_error` | `(LLMChain.t(), Message.t() -> any())` | Message processing failed |
| `on_tool_response_created` | `(LLMChain.t(), Message.t() -> any())` | Tool execution generated results |
| `on_retries_exceeded` | `(LLMChain.t() -> any())` | Max retry count exhausted |

**Important**: Callback return values are discarded. Use side effects (HTTP calls) only.

### Key Discoveries

- `on_llm_new_delta` receives a **list** of `MessageDelta` structs, not a single delta
- Token usage arrives via `on_llm_token_usage` callback, separate from message callbacks
- Process dictionary can correlate data across callbacks (same process)
- LangChain allows multiple callback handlers via chained `add_callback/2` calls

## Desired End State

After implementation:

```elixir
alias LangChain.Chains.LLMChain
alias LangChain.ChatModels.ChatOpenAI
alias LangChain.Message
alias Braintrust.LangChain, as: BraintrustCallbacks

# Basic usage - automatic observability
{:ok, chain} =
  %{llm: ChatOpenAI.new!(%{model: "gpt-4"})}
  |> LLMChain.new!()
  |> LLMChain.add_callback(BraintrustCallbacks.handler(
    project_id: "proj_xxx",
    metadata: %{"environment" => "production"},
    tags: ["chat"]
  ))
  |> LLMChain.add_message(Message.new_user!("Hello!"))
  |> LLMChain.run()

# All LLM interactions logged to Braintrust with:
# - Input in OpenAI message format (enables "Try prompt" button)
# - Output content
# - Token usage metrics (input_tokens, output_tokens)
# - Model and provider metadata
# - Custom metadata and tags
```

### Verification

1. Run `mix test` - all tests pass
2. Run `mix quality` - all quality checks pass
3. Manual test with real LangChain + Braintrust API key shows logs in Braintrust UI

## What We're NOT Doing

- **No async batching** - LLM latency dominates; sync is fine
- **No OpenTelemetry integration** - Future enhancement, separate issue
- **No automatic span hierarchy** - Single spans per LLM call (trace hierarchy is future work)
- **No streaming delta logging** - Only final message logged (streaming_handler tracks metrics only)
- **No rate limit handling in callbacks** - Rely on existing Client retry logic

## Implementation Approach

Use process dictionary to correlate token usage with messages across callbacks:
1. `on_llm_token_usage` stores usage via `Process.put/2`
2. `on_message_processed` retrieves usage and logs complete span

Primary logging happens in `on_message_processed` because:
- Fires for both streaming and non-streaming
- Message is complete at this point
- Can include tool call information

---

## Phase 1: Core Callback Handler

### Overview

Implement `Braintrust.LangChain.handler/1` that creates a callback map for basic LLM logging.

### Changes Required

#### 1. Add Optional Dependency

**File**: `mix.exs`
**Changes**: Add langchain as optional dependency

```elixir
defp deps do
  [
    {:req, "~> 0.5"},
    {:jason, "~> 1.4"},
    {:langchain, "~> 0.4", optional: true},
    # ... rest of deps
  ]
end
```

#### 2. Create LangChain Module

**File**: `lib/braintrust/langchain.ex`
**Changes**: New module with handler/1 function

```elixir
defmodule Braintrust.LangChain do
  @moduledoc """
  LangChain callback handler for Braintrust observability.

  Automatically logs LLM interactions to Braintrust when used with
  LangChain's LLMChain.

  ## Usage

      alias LangChain.Chains.LLMChain
      alias LangChain.ChatModels.ChatOpenAI
      alias LangChain.Message
      alias Braintrust.LangChain, as: BraintrustCallbacks

      {:ok, chain} =
        %{llm: ChatOpenAI.new!(%{model: "gpt-4"})}
        |> LLMChain.new!()
        |> LLMChain.add_callback(BraintrustCallbacks.handler(
          project_id: "proj_xxx",
          metadata: %{"environment" => "production"},
          tags: ["chat"]
        ))
        |> LLMChain.add_message(Message.new_user!("Hello!"))
        |> LLMChain.run()

  ## Options

    * `:project_id` - Braintrust project ID (required)
    * `:metadata` - Additional metadata to attach to all spans (default: %{})
    * `:tags` - Tags to attach to spans (default: [])
    * `:api_key` - Override API key for logging requests
    * `:base_url` - Override base URL for logging requests

  ## What Gets Logged

  Each LLM interaction creates a log entry with:

    * `input` - Messages in OpenAI format (enables "Try prompt" button in UI)
    * `output` - Assistant response content
    * `metadata` - Model name, provider, status, plus custom metadata
    * `metrics` - Token usage (input_tokens, output_tokens, total_tokens)
    * `tags` - Custom tags
    * `error` - Error information if processing failed

  """

  alias Braintrust.Log

  # Process dictionary keys for cross-callback correlation
  @token_usage_key :braintrust_langchain_token_usage
  @request_start_key :braintrust_langchain_request_start

  @type handler_opts :: [
          project_id: String.t(),
          metadata: map(),
          tags: [String.t()],
          api_key: String.t(),
          base_url: String.t()
        ]

  @doc """
  Creates a callback handler map for use with LLMChain.

  ## Examples

      handler = Braintrust.LangChain.handler(project_id: "proj_xxx")

      chain
      |> LLMChain.add_callback(handler)
      |> LLMChain.run()

  """
  @spec handler(handler_opts()) :: map()
  def handler(opts) do
    project_id = Keyword.fetch!(opts, :project_id)
    base_metadata = Keyword.get(opts, :metadata, %{})
    tags = Keyword.get(opts, :tags, [])
    log_opts = Keyword.take(opts, [:api_key, :base_url])

    %{
      on_llm_token_usage: fn _chain, usage ->
        store_token_usage(usage)
      end,
      on_message_processed: fn chain, message ->
        log_processed_message(project_id, chain, message, base_metadata, tags, log_opts)
      end,
      on_message_processing_error: fn chain, message ->
        log_error(project_id, chain, message, base_metadata, tags, log_opts)
      end,
      on_tool_response_created: fn chain, message ->
        log_tool_response(project_id, chain, message, base_metadata, tags, log_opts)
      end,
      on_retries_exceeded: fn chain ->
        log_retries_exceeded(project_id, chain, base_metadata, tags, log_opts)
      end
    }
  end

  # Token usage storage (process dictionary)

  defp store_token_usage(usage) do
    Process.put(@token_usage_key, usage)
  end

  defp get_and_clear_token_usage do
    usage = Process.get(@token_usage_key)
    Process.delete(@token_usage_key)
    usage
  end

  # Logging functions

  defp log_processed_message(project_id, chain, message, base_metadata, tags, opts) do
    # Only log assistant messages (not user/system/tool)
    if message.role == :assistant do
      usage = get_and_clear_token_usage()

      event = %{
        input: format_input(chain),
        output: format_output(message),
        metadata: build_metadata(chain, message, base_metadata),
        metrics: build_metrics(usage),
        tags: tags
      }

      Log.insert(project_id, [event], opts)
    end

    :ok
  end

  defp log_error(project_id, chain, message, base_metadata, tags, opts) do
    event = %{
      input: format_input(chain),
      output: format_output(message),
      error: "Message processing error",
      metadata: Map.merge(base_metadata, %{
        "error" => true,
        "status" => to_string(message.status),
        "model" => get_model_name(chain),
        "provider" => get_provider_name(chain)
      }),
      tags: ["error" | tags]
    }

    Log.insert(project_id, [event], opts)
  end

  defp log_tool_response(project_id, chain, message, base_metadata, tags, opts) do
    tool_results = message.tool_results || []

    event = %{
      input: format_tool_input(tool_results),
      output: format_output(message),
      metadata: Map.merge(base_metadata, %{
        "span_type" => "tool",
        "tool_count" => length(tool_results),
        "model" => get_model_name(chain),
        "provider" => get_provider_name(chain)
      }),
      tags: ["tool" | tags]
    }

    Log.insert(project_id, [event], opts)
  end

  defp log_retries_exceeded(project_id, chain, base_metadata, tags, opts) do
    event = %{
      input: format_input(chain),
      output: nil,
      error: "Max retries exceeded",
      metadata: Map.merge(base_metadata, %{
        "max_retry_count" => chain.max_retry_count,
        "failure_count" => chain.current_failure_count,
        "model" => get_model_name(chain),
        "provider" => get_provider_name(chain)
      }),
      tags: ["error", "retries_exceeded" | tags]
    }

    Log.insert(project_id, [event], opts)
  end

  # Input/Output formatting

  defp format_input(chain) do
    messages = chain.messages || []

    %{
      "messages" => Enum.map(messages, fn msg ->
        %{
          "role" => to_string(msg.role),
          "content" => format_content(msg.content)
        }
      end)
    }
  end

  defp format_tool_input(tool_results) do
    %{
      "tool_results" => Enum.map(tool_results, fn result ->
        %{
          "name" => result.name,
          "tool_call_id" => result.tool_call_id,
          "content" => format_content(result.content),
          "is_error" => result.is_error || false
        }
      end)
    }
  end

  defp format_output(message) do
    format_content(message.content)
  end

  defp format_content(content) when is_binary(content), do: content
  defp format_content(nil), do: nil
  defp format_content([]), do: nil

  defp format_content(content) when is_list(content) do
    # Handle ContentPart list - extract text parts
    content
    |> Enum.map(&format_content_part/1)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      [single] -> single
      multiple -> multiple
    end
  end

  defp format_content(other), do: inspect(other)

  defp format_content_part(%{type: :text, content: text}), do: text
  defp format_content_part(%{type: :text} = part), do: Map.get(part, :content) || Map.get(part, :text)
  defp format_content_part(%{type: type}), do: %{"type" => to_string(type), "content" => "[binary data]"}
  defp format_content_part(text) when is_binary(text), do: text
  defp format_content_part(_other), do: nil

  # Metadata building

  defp build_metadata(chain, message, base_metadata) do
    Map.merge(base_metadata, %{
      "model" => get_model_name(chain),
      "provider" => get_provider_name(chain),
      "status" => to_string(message.status),
      "has_tool_calls" => has_tool_calls?(message)
    })
  end

  defp has_tool_calls?(message) do
    case message.tool_calls do
      nil -> false
      [] -> false
      _ -> true
    end
  end

  # Metrics building

  defp build_metrics(nil), do: %{}

  defp build_metrics(usage) do
    %{
      "input_tokens" => usage.input,
      "output_tokens" => usage.output,
      "total_tokens" => total_tokens(usage)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp total_tokens(usage) do
    case {usage.input, usage.output} do
      {nil, nil} -> nil
      {input, nil} -> input
      {nil, output} -> output
      {input, output} -> input + output
    end
  end

  # Chain introspection

  defp get_model_name(chain) do
    case chain.llm do
      %{model: model} when is_binary(model) -> model
      _ -> "unknown"
    end
  end

  defp get_provider_name(chain) do
    chain.llm.__struct__
    |> Module.split()
    |> List.last()
    |> String.replace_leading("Chat", "")
    |> String.downcase()
  rescue
    _ -> "unknown"
  end
end
```

#### 3. Create Tests

**File**: `test/braintrust/langchain_test.exs`
**Changes**: New test file

```elixir
defmodule Braintrust.LangChainTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Braintrust.LangChain

  # Mock LangChain structs for testing (since langchain is optional)
  defmodule MockChain do
    defstruct [:llm, :messages, :max_retry_count, :current_failure_count]
  end

  defmodule MockLLM do
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
      handler = LangChain.handler(project_id: "proj_123")

      assert is_map(handler)
      assert Map.has_key?(handler, :on_llm_token_usage)
      assert Map.has_key?(handler, :on_message_processed)
      assert Map.has_key?(handler, :on_message_processing_error)
      assert Map.has_key?(handler, :on_tool_response_created)
      assert Map.has_key?(handler, :on_retries_exceeded)
    end

    test "raises if project_id is missing" do
      assert_raise KeyError, fn ->
        LangChain.handler([])
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

      handler = LangChain.handler(project_id: "proj_123")

      chain = %MockChain{
        llm: %MockLLM{model: "gpt-4"},
        messages: [
          %MockMessage{role: :user, content: "Hi", status: :complete, tool_calls: nil, tool_results: nil}
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

      handler = LangChain.handler(project_id: "proj_123")

      # Simulate token usage callback first
      usage = %MockTokenUsage{input: 10, output: 20}
      handler.on_llm_token_usage.(nil, usage)

      chain = %MockChain{
        llm: %MockLLM{model: "gpt-4"},
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
      handler = LangChain.handler(project_id: "proj_123")

      chain = %MockChain{llm: %MockLLM{model: "gpt-4"}, messages: []}
      message = %MockMessage{role: :user, content: "Hi", status: :complete, tool_calls: nil, tool_results: nil}

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

      handler = LangChain.handler(
        project_id: "proj_123",
        metadata: %{"environment" => "test", "custom_key" => "custom_value"},
        tags: ["tag1", "tag2"]
      )

      chain = %MockChain{llm: %MockLLM{model: "gpt-4"}, messages: []}
      message = %MockMessage{role: :assistant, content: "Hi", status: :complete, tool_calls: nil, tool_results: nil}

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

      handler = LangChain.handler(project_id: "proj_123")

      chain = %MockChain{llm: %MockLLM{model: "gpt-4"}, messages: []}
      message = %MockMessage{role: :assistant, content: nil, status: :cancelled, tool_calls: nil, tool_results: nil}

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

      handler = LangChain.handler(project_id: "proj_123")

      chain = %MockChain{
        llm: %MockLLM{model: "gpt-4"},
        messages: [],
        max_retry_count: 3,
        current_failure_count: 4
      }

      handler.on_retries_exceeded.(chain)
    end
  end
end
```

### Success Criteria

#### Automated Verification:
- [x] `mix deps.get` succeeds with optional langchain dependency
- [x] `mix compile` succeeds (no compilation errors)
- [x] `mix test test/braintrust/langchain_test.exs` passes
- [x] `mix format --check-formatted` passes
- [x] `mix quality` passes

#### Manual Verification:
- [x] Create a test script that uses real LangChain + handler with a Braintrust API key
- [x] Verify logs appear in Braintrust UI
- [x] Verify "Try prompt" button works (input is in OpenAI format)
- [x] Verify token metrics appear correctly

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: Streaming Support

### Overview

Add `Braintrust.LangChain.streaming_handler/1` that tracks streaming metrics like time-to-first-token.

### Changes Required

#### 1. Add Streaming Handler

**File**: `lib/braintrust/langchain.ex`
**Changes**: Add streaming_handler/1 function and delta tracking

```elixir
# Add to module attributes
@first_token_time_key :braintrust_langchain_first_token_time
@request_start_key :braintrust_langchain_request_start

@doc """
Creates a streaming-aware callback handler.

In addition to the standard handler callbacks, this tracks:

  * Time-to-first-token (TTFT) - Time from request start to first delta
  * Streaming duration - Total time for all deltas

## Usage

    handler = Braintrust.LangChain.streaming_handler(
      project_id: "proj_xxx",
      tags: ["streaming"]
    )

    %{llm: ChatOpenAI.new!(%{model: "gpt-4", stream: true})}
    |> LLMChain.new!()
    |> LLMChain.add_callback(handler)
    |> LLMChain.run()

"""
@spec streaming_handler(handler_opts()) :: map()
def streaming_handler(opts) do
  base_handler = handler(opts)

  Map.merge(base_handler, %{
    on_llm_new_delta: fn _chain, deltas ->
      track_streaming_delta(deltas)
    end
  })
end

# Update log_processed_message to include streaming metrics
defp log_processed_message(project_id, chain, message, base_metadata, tags, opts) do
  if message.role == :assistant do
    usage = get_and_clear_token_usage()
    streaming_metrics = get_and_clear_streaming_metrics()

    event = %{
      input: format_input(chain),
      output: format_output(message),
      metadata: build_metadata(chain, message, base_metadata),
      metrics: Map.merge(build_metrics(usage), streaming_metrics),
      tags: tags
    }

    Log.insert(project_id, [event], opts)
  end

  :ok
end

# Streaming metrics tracking

defp track_streaming_delta(deltas) when is_list(deltas) do
  now = System.monotonic_time(:millisecond)

  # Record request start on first delta batch
  if is_nil(Process.get(@request_start_key)) do
    Process.put(@request_start_key, now)
  end

  # Record first token time
  if is_nil(Process.get(@first_token_time_key)) and has_content?(deltas) do
    Process.put(@first_token_time_key, now)
  end
end

defp has_content?(deltas) do
  Enum.any?(deltas, fn delta ->
    delta.content != nil and delta.content != "" and delta.content != []
  end)
end

defp get_and_clear_streaming_metrics do
  request_start = Process.get(@request_start_key)
  first_token_time = Process.get(@first_token_time_key)

  Process.delete(@request_start_key)
  Process.delete(@first_token_time_key)

  now = System.monotonic_time(:millisecond)

  metrics = %{}

  metrics = if first_token_time && request_start do
    Map.put(metrics, "time_to_first_token_ms", first_token_time - request_start)
  else
    metrics
  end

  metrics = if request_start do
    Map.put(metrics, "streaming_duration_ms", now - request_start)
  else
    metrics
  end

  metrics
end
```

#### 2. Add Streaming Tests

**File**: `test/braintrust/langchain_test.exs`
**Changes**: Add streaming handler tests

```elixir
describe "streaming_handler/1" do
  test "includes on_llm_new_delta callback" do
    handler = LangChain.streaming_handler(project_id: "proj_123")

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

    handler = LangChain.streaming_handler(project_id: "proj_123")

    # Simulate delta callbacks
    delta = %{content: "Hello", status: :incomplete}
    handler.on_llm_new_delta.(nil, [delta])

    # Small delay to ensure measurable time
    Process.sleep(10)

    chain = %MockChain{llm: %MockLLM{model: "gpt-4"}, messages: []}
    message = %MockMessage{role: :assistant, content: "Hello!", status: :complete, tool_calls: nil, tool_results: nil}

    handler.on_message_processed.(chain, message)
  end
end
```

### Success Criteria

#### Automated Verification:
- [x] `mix test test/braintrust/langchain_test.exs` passes (including streaming tests)
- [x] `mix quality` passes

#### Manual Verification:
- [x] Test with streaming LLM call (`stream: true`)
- [x] Verify `time_to_first_token_ms` metric appears in Braintrust
- [x] Verify `streaming_duration_ms` metric appears in Braintrust

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 3: Documentation and Polish

### Overview

Add comprehensive documentation, doctests, and ensure the module integrates well with the rest of the SDK.

### Changes Required

#### 1. Add Module to Main Braintrust Module Docs

**File**: `lib/braintrust.ex`
**Changes**: Add LangChain to module documentation

Add to the moduledoc's list of modules:
```elixir
* `Braintrust.LangChain` - LangChain callback handler for observability
```

#### 2. Update README

**File**: `README.md`
**Changes**: Add LangChain integration section

```markdown
## LangChain Integration

If you're using [LangChain Elixir](https://github.com/brainlid/langchain), you can automatically log all LLM interactions to Braintrust:

```elixir
alias LangChain.Chains.LLMChain
alias LangChain.ChatModels.ChatOpenAI
alias LangChain.Message
alias Braintrust.LangChain, as: BraintrustCallbacks

{:ok, chain} =
  %{llm: ChatOpenAI.new!(%{model: "gpt-4"})}
  |> LLMChain.new!()
  |> LLMChain.add_callback(BraintrustCallbacks.handler(
    project_id: "your-project-id",
    metadata: %{"environment" => "production"}
  ))
  |> LLMChain.add_message(Message.new_user!("Hello!"))
  |> LLMChain.run()
```

For streaming with time-to-first-token metrics:

```elixir
|> LLMChain.add_callback(BraintrustCallbacks.streaming_handler(
  project_id: "your-project-id"
))
```
```

#### 3. Add Doctests to LangChain Module

**File**: `lib/braintrust/langchain.ex`
**Changes**: Ensure doctests work (may need to skip if langchain not present)

Add at top of module:
```elixir
# Skip doctests if langchain is not available
@moduledoc """
...existing docs...

> #### Optional Dependency {: .info}
>
> This module requires the `langchain` package. Add it to your dependencies:
>
>     {:langchain, "~> 0.4"}
>
"""
```

### Success Criteria

#### Automated Verification:
- [x] `mix docs` generates documentation without warnings
- [x] `mix quality` passes
- [x] All tests pass

#### Manual Verification:
- [ ] Documentation renders correctly on HexDocs (after publish)
- [ ] README examples are clear and complete
- [ ] Module docs include all options and examples

---

## Testing Strategy

### Unit Tests

Located in `test/braintrust/langchain_test.exs`:

- `handler/1` returns correct callback map structure
- `handler/1` raises on missing project_id
- `on_message_processed` logs assistant messages with correct format
- `on_message_processed` includes token usage when available
- `on_message_processed` skips non-assistant messages
- `on_message_processed` includes custom metadata and tags
- `on_message_processing_error` logs with error tag
- `on_retries_exceeded` logs retry failures
- `on_tool_response_created` logs tool executions
- `streaming_handler/1` includes delta callback
- `streaming_handler/1` tracks TTFT metrics

### Integration Tests

Create `test/integration/langchain_integration_test.exs` (only runs when langchain is available):

```elixir
# Only run if langchain is compiled
if Code.ensure_loaded?(LangChain.Chains.LLMChain) do
  defmodule Braintrust.LangChainIntegrationTest do
    use ExUnit.Case, async: false

    @moduletag :integration
    @moduletag :external

    # Tests that require real API keys
    # Run with: mix test --only integration
  end
end
```

### Manual Testing Steps

1. Create a test Elixir project with both `braintrust` and `langchain`
2. Configure a real Braintrust API key
3. Run a simple LLM chain with the handler
4. Verify in Braintrust UI:
   - Log entry appears
   - Input shows messages in correct format
   - "Try prompt" button works
   - Token metrics are present
   - Custom metadata and tags appear

---

## Performance Considerations

- **Synchronous logging**: Each LLM call makes one HTTP request to Braintrust. Given LLM calls take 500ms-5s, this adds ~50-200ms overhead (acceptable).
- **No batching**: Single events logged per callback. Future optimization could batch multiple tool calls.
- **Process dictionary**: Minimal overhead for cross-callback correlation.

---

## Migration Notes

This is a new feature with no migration required. Users opt-in by:

1. Adding `{:langchain, "~> 0.4"}` to their deps (if not already present)
2. Adding the callback handler to their LLMChain

---

## References

- Source issue: GitHub #25
- Research document: `thoughts/shared/research/braintrust_hex_package.md` (lines 1490-2089)
- LangChain Elixir: https://github.com/brainlid/langchain
- ChainCallbacks docs: https://hexdocs.pm/langchain/LangChain.Chains.ChainCallbacks.html
- Existing Log module: `lib/braintrust/log.ex`
- Existing Span struct: `lib/braintrust/span.ex`
