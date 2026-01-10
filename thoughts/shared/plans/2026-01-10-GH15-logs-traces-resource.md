# Logs and Traces Resource Implementation Plan

## Overview

Implement the `Braintrust.Log` module and `Braintrust.Span` struct for production observability of AI applications. This is the core tracing functionality that enables logging LLM interactions to Braintrust.

**Key design decisions:**
- `Braintrust.Span` will be a **separate module** (`lib/braintrust/span.ex`) since it's shared across experiments, datasets, and logs
- `Log.insert/3` will accept **both** `%Span{}` structs and raw maps for flexibility
- The Log API is **write-only** - only `insert/3` operation (no list/get/delete via REST)

## Current State Analysis

### Existing Patterns

The codebase has established patterns for resource modules:

- **Experiment module** (`lib/braintrust/experiment.ex:1-554`): CRUD + data operations including `insert/3` that accepts a list of maps
- **Client module** (`lib/braintrust/client.ex`): HTTP client with `get/3`, `post/4`, `patch/4`, `delete/3`
- **Resource module** (`lib/braintrust/resource.ex:1-73`): Shared helpers for list/stream operations

### Key Discoveries

1. **Log endpoint is unique**: `POST /v1/project_logs/{project_id}/insert` (not `/v1/log`)
2. **Write-only API**: No list/get/delete endpoints for logs
3. **Span hierarchy**: DAG structure with `span_id`, `root_span_id`, `span_parents`
4. **Input format**: OpenAI message format recommended for UI integration
5. **Scores vs Metrics**: Scores are 0-1 normalized, metrics are raw numbers summed during aggregation

## Desired End State

A fully implemented logging system with:

1. `%Braintrust.Span{}` struct with all fields from the API specification
2. `Braintrust.Log.insert/3` that accepts project_id, events (maps or Span structs), and options
3. Updated `Braintrust.Experiment.insert/3` to also accept Span structs
4. Updated `Braintrust.Dataset.insert/3` to also accept Span structs
5. Comprehensive doctests demonstrating common usage patterns
6. Unit tests with mocked HTTP responses

### Verification

- All quality checks pass: `mix quality`
- Doctests execute successfully: `mix test`
- Module follows established patterns (function signatures, error handling)

## What We're NOT Doing

- **No fetch/list operations**: Logs API is write-only via REST
- **No OpenTelemetry integration**: Out of scope for this ticket (future enhancement)
- **No async/batching optimizations**: Basic synchronous API only
- **No automatic span hierarchy management**: SDK-managed fields documented but not auto-set
- **No span_id generation**: Users provide their own IDs or let Braintrust auto-generate

## Implementation Approach

1. Create `Braintrust.Span` as a standalone struct module with type specs
2. Create `Braintrust.Log` module with `insert/3` function
3. Update `Braintrust.Experiment.insert/3` to also accept Span structs
4. Update `Braintrust.Dataset.insert/3` to also accept Span structs
5. Support both raw maps and Span structs across all insert functions
6. Follow existing patterns and maintain backward compatibility

---

## Phase 1: Span Struct Module

### Overview

Create the `Braintrust.Span` struct module with all fields and type specifications.

### Changes Required

#### 1. Create Span Module

**File**: `lib/braintrust/span.ex`

```elixir
defmodule Braintrust.Span do
  @moduledoc """
  Represents a span in a Braintrust trace.

  Spans are the core data structure for logging AI interactions. They capture
  input/output pairs, scores, metrics, and metadata for observability.

  ## Structure

  Traces in Braintrust form a directed acyclic graph (DAG) of spans:
  - A **trace** corresponds to a single request/interaction
  - A **span** is a unit of work within a trace (e.g., single LLM call, tool invocation)
  - Each span can have multiple parents (supporting DAG structure)
  - Most executions form a simple tree

  ## Fields

  ### Core Fields

    * `:id` - Unique identifier for the span (UUID, auto-generated if not provided)
    * `:span_id` - Span identifier for tracing (SDK-managed)
    * `:root_span_id` - Root span of the trace (SDK-managed)
    * `:span_parents` - Parent span IDs (SDK-managed, supports DAG structure)

  ### Data Fields

    * `:input` - Input data (OpenAI message format recommended for UI support)
    * `:output` - Output/response from the task
    * `:expected` - Expected output for scoring (optional)
    * `:error` - Error information if applicable

  ### Scoring Fields

    * `:scores` - Score values normalized to 0-1 range, keyed by score name
    * `:metrics` - Raw numeric values that get summed during aggregation

  ### Metadata Fields

    * `:metadata` - String keys with JSON-serializable values
    * `:tags` - String tags (only on top-level spans/traces)
    * `:created_at` - ISO 8601 timestamp

  ## Input Format

  For best UI integration, format input as OpenAI message format:

      %Braintrust.Span{
        input: %{
          messages: [
            %{role: "system", content: "You are helpful."},
            %{role: "user", content: "Hello!"}
          ]
        },
        output: "Hi there!"
      }

  ## Scores vs Metrics

    * **Scores**: Values normalized to [0, 1] range (e.g., accuracy, relevance)
    * **Metrics**: Raw numbers that cannot be normalized (e.g., latency_ms, token_count)

  ## Examples

      # Basic span
      span = %Braintrust.Span{
        input: %{messages: [%{role: "user", content: "What is 2+2?"}]},
        output: "4",
        scores: %{accuracy: 1.0}
      }

      # Span with metadata and metrics
      span = %Braintrust.Span{
        input: %{messages: [%{role: "user", content: "Hello"}]},
        output: "Hi there!",
        scores: %{quality: 0.9, relevance: 0.85},
        metadata: %{model: "gpt-4", environment: "production"},
        metrics: %{latency_ms: 250, input_tokens: 50, output_tokens: 25}
      }

  ## Auto-Managed Fields

  The following fields are typically managed by the SDK and should not be set manually:

    * `span_id`, `root_span_id`, `span_parents` - Trace hierarchy
    * `project_id`, `experiment_id`, `dataset_id`, `log_id` - Context IDs

  """

  @type t :: %__MODULE__{
          id: String.t() | nil,
          span_id: String.t() | nil,
          root_span_id: String.t() | nil,
          span_parents: [String.t()] | nil,
          input: map() | nil,
          output: any(),
          expected: any(),
          scores: map() | nil,
          metadata: map() | nil,
          metrics: map() | nil,
          tags: [String.t()] | nil,
          created_at: DateTime.t() | String.t() | nil,
          error: String.t() | nil
        }

  defstruct [
    :id,
    :span_id,
    :root_span_id,
    :span_parents,
    :input,
    :output,
    :expected,
    :scores,
    :metadata,
    :metrics,
    :tags,
    :created_at,
    :error
  ]

  @doc """
  Converts a Span struct to a map suitable for API submission.

  Removes nil values to avoid sending empty fields to the API.

  ## Examples

      iex> span = %Braintrust.Span{
      ...>   input: %{query: "test"},
      ...>   output: "result",
      ...>   scores: %{quality: 0.9}
      ...> }
      iex> map = Braintrust.Span.to_map(span)
      iex> map[:input]
      %{query: "test"}
      iex> Map.has_key?(map, :id)
      false

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = span) do
    span
    |> Map.from_struct()
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end
end
```

### Success Criteria

#### Automated Verification
- [x] Module compiles: `mix compile`
- [x] Code formatting passes: `mix format --check-formatted`
- [x] Doctests pass: `mix test`

#### Manual Verification
- [x] Struct definition matches API specification from GitHub issue
- [x] Module documentation is comprehensive

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: Log Module

### Overview

Implement the `Braintrust.Log` module with the `insert/3` function for submitting production logs.

### Changes Required

#### 1. Create Log Module

**File**: `lib/braintrust/log.ex`

```elixir
defmodule Braintrust.Log do
  @moduledoc """
  Log production traces to Braintrust for observability.

  The Log module provides functionality to submit production logs and traces
  for AI applications. Unlike other resources (Project, Experiment, Dataset),
  the Log API is **write-only** - there are no list, get, or delete operations.

  ## Overview

  Production logging enables:
  - Observability of AI interactions in production
  - Quality monitoring via scores and metrics
  - Debugging and analysis of real-world usage
  - Performance tracking across deployments

  ## Examples

      # Log a simple interaction
      {:ok, result} = Braintrust.Log.insert("proj_123", [
        %{
          input: %{messages: [%{role: "user", content: "Hello"}]},
          output: "Hi there!",
          scores: %{quality: 0.9},
          metadata: %{model: "gpt-4", environment: "production"}
        }
      ])

      # Log with metrics
      {:ok, result} = Braintrust.Log.insert("proj_123", [
        %{
          input: %{messages: [%{role: "user", content: "Summarize this"}]},
          output: "Here's a summary...",
          metrics: %{latency_ms: 250, input_tokens: 500, output_tokens: 100},
          tags: ["production", "summarization"]
        }
      ])

      # Using Span structs
      spans = [
        %Braintrust.Span{
          input: %{messages: [%{role: "user", content: "test"}]},
          output: "response",
          scores: %{accuracy: 0.95}
        }
      ]
      {:ok, result} = Braintrust.Log.insert("proj_123", spans)

  ## Input Format

  For best UI integration (including the "Try prompt" button), format input
  as OpenAI message format:

      %{
        messages: [
          %{role: "system", content: "You are helpful."},
          %{role: "user", content: "Hello!"}
        ]
      }

  ## Scores vs Metrics

    * **Scores**: Values normalized to [0, 1] range (e.g., accuracy: 0.9)
    * **Metrics**: Raw numbers that get summed during aggregation (e.g., latency_ms: 250)

  ## Tags

  Tags are string labels applied to top-level spans (traces). They should only
  be set on the root span of a trace, not on subspans.

  ## Batching

  The `insert/3` function accepts a list of events, enabling batch submission
  for improved performance. Consider batching multiple spans in a single request
  when logging high-volume production traffic.

  """

  alias Braintrust.{Client, Error, Span}

  @api_path "/v1/project_logs"

  @doc """
  Inserts log events/spans for a project.

  ## Parameters

    * `project_id` - The project ID to log events to
    * `events` - List of event maps or `%Braintrust.Span{}` structs, each containing:
      * `:input` - Input data (OpenAI message format recommended)
      * `:output` - Output/response from the task
      * `:expected` - Expected output for scoring (optional)
      * `:scores` - Map of score names to values (0-1 range)
      * `:metadata` - Custom metadata map (string keys, JSON-serializable values)
      * `:metrics` - Numeric metrics (e.g., latency_ms, token_count)
      * `:tags` - String tags (only on top-level spans)
      * `:error` - Error information if applicable

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Returns

    * `{:ok, map()}` - Success response with row IDs
    * `{:error, %Braintrust.Error{}}` - Error response

  ## Examples

      # Log with raw maps
      iex> {:ok, result} = Braintrust.Log.insert("proj_123", [
      ...>   %{
      ...>     input: %{messages: [%{role: "user", content: "Hello"}]},
      ...>     output: "Hi there!",
      ...>     scores: %{quality: 0.9}
      ...>   }
      ...> ])

      # Log with Span structs
      iex> spans = [%Braintrust.Span{input: %{q: "test"}, output: "result"}]
      iex> {:ok, result} = Braintrust.Log.insert("proj_123", spans)

      # Log with metadata and metrics
      iex> {:ok, result} = Braintrust.Log.insert("proj_123", [
      ...>   %{
      ...>     input: %{messages: [%{role: "user", content: "Summarize"}]},
      ...>     output: "Summary...",
      ...>     metadata: %{model: "gpt-4", environment: "production"},
      ...>     metrics: %{latency_ms: 250, input_tokens: 100}
      ...>   }
      ...> ])

  """
  @spec insert(String.t(), [map() | Span.t()], keyword()) :: {:ok, map()} | {:error, Error.t()}
  def insert(project_id, events, opts \\ []) when is_binary(project_id) and is_list(events) do
    client = Client.new(opts)
    normalized_events = Enum.map(events, &normalize_event/1)
    body = %{events: normalized_events}

    Client.post(client, "#{@api_path}/#{project_id}/insert", body)
  end

  # Private Functions

  defp normalize_event(%Span{} = span), do: Span.to_map(span)
  defp normalize_event(event) when is_map(event), do: event
end
```

### Success Criteria

#### Automated Verification
- [x] Module compiles: `mix compile`
- [x] Code formatting passes: `mix format --check-formatted`
- [x] Credo passes: `mix credo --strict`

#### Manual Verification
- [x] Function signature matches the spec in GitHub issue
- [x] Both maps and Span structs are accepted

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 3: Unit Tests

### Overview

Create comprehensive unit tests for the Span struct and Log module.

### Changes Required

#### 1. Create Span Test File

**File**: `test/braintrust/span_test.exs`

```elixir
defmodule Braintrust.SpanTest do
  use ExUnit.Case, async: true

  alias Braintrust.Span

  describe "struct" do
    test "creates span with all fields" do
      span = %Span{
        id: "span_123",
        span_id: "s_123",
        root_span_id: "r_123",
        span_parents: ["p_123"],
        input: %{messages: [%{role: "user", content: "Hello"}]},
        output: "Hi there!",
        expected: "A greeting",
        scores: %{quality: 0.9},
        metadata: %{model: "gpt-4"},
        metrics: %{latency_ms: 250},
        tags: ["production"],
        created_at: ~U[2024-01-15 14:15:22Z],
        error: nil
      }

      assert span.id == "span_123"
      assert span.input == %{messages: [%{role: "user", content: "Hello"}]}
      assert span.scores == %{quality: 0.9}
    end

    test "creates span with minimal fields" do
      span = %Span{
        input: %{query: "test"},
        output: "result"
      }

      assert span.input == %{query: "test"}
      assert span.output == "result"
      assert span.scores == nil
    end
  end

  describe "to_map/1" do
    test "converts span to map removing nil values" do
      span = %Span{
        input: %{query: "test"},
        output: "result",
        scores: %{quality: 0.9}
      }

      map = Span.to_map(span)

      assert map[:input] == %{query: "test"}
      assert map[:output] == "result"
      assert map[:scores] == %{quality: 0.9}
      refute Map.has_key?(map, :id)
      refute Map.has_key?(map, :metadata)
      refute Map.has_key?(map, :error)
    end

    test "preserves all non-nil values" do
      span = %Span{
        id: "span_123",
        input: %{messages: []},
        output: "response",
        expected: "expected",
        scores: %{accuracy: 1.0},
        metadata: %{env: "test"},
        metrics: %{latency_ms: 100},
        tags: ["test"],
        error: "Something went wrong"
      }

      map = Span.to_map(span)

      assert map[:id] == "span_123"
      assert map[:input] == %{messages: []}
      assert map[:output] == "response"
      assert map[:expected] == "expected"
      assert map[:scores] == %{accuracy: 1.0}
      assert map[:metadata] == %{env: "test"}
      assert map[:metrics] == %{latency_ms: 100}
      assert map[:tags] == ["test"]
      assert map[:error] == "Something went wrong"
    end

    test "handles span_parents list" do
      span = %Span{
        input: %{},
        span_parents: ["parent_1", "parent_2"]
      }

      map = Span.to_map(span)

      assert map[:span_parents] == ["parent_1", "parent_2"]
    end
  end
end
```

#### 2. Create Log Test File

**File**: `test/braintrust/log_test.exs`

```elixir
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
        [event1, event2] = opts[:json][:events]

        # Map event unchanged
        assert event1 == %{input: %{q: "map"}, output: "map result"}

        # Span converted to map
        assert event2[:input] == %{q: "span"}
        assert event2[:output] == "span result"

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
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["r1", "r2", "r3", "r4", "r5"]}, headers: []}}
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
        {:ok, %Req.Response{status: 404, body: %{"error" => %{"message" => "Project not found"}}, headers: []}}
      end)

      assert {:error, %Error{type: :not_found}} = Log.insert("invalid_proj", [%{input: %{}}])
    end

    test "returns error on unauthorized" do
      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 401, body: %{"error" => "Unauthorized"}, headers: []}}
      end)

      assert {:error, %Error{type: :unauthorized}} = Log.insert("proj_123", [%{input: %{}}])
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
```

### Success Criteria

#### Automated Verification
- [x] All quality checks pass: `mix quality`
- [x] Tests pass: `mix test`
- [x] Test coverage is comprehensive for all functions

#### Manual Verification
- [x] Test patterns match those in `experiment_test.exs`
- [x] Edge cases are properly covered

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 4: Integration and Documentation

### Overview

Finalize the implementation by ensuring all doctests work and verifying documentation.

### Changes Required

#### 1. Verify Doctests

Run `mix test` to ensure all doctests in the module documentation execute correctly.

#### 2. Verify Documentation Generation

Run `mix docs` to ensure documentation generates correctly.

### Success Criteria

#### Automated Verification
- [x] All quality checks pass: `mix quality`
- [x] All tests pass: `mix test`
- [x] Documentation generates correctly: `mix docs`

#### Manual Verification
- [x] Modules are accessible in IEx: `iex -S mix`
  - `Braintrust.Span` struct can be created
  - `Braintrust.Log.insert/3` accepts both maps and Span structs
- [x] Documentation renders correctly in generated docs
- [x] No warnings during compilation

**Implementation Note**: After completing this phase and all automated verification passes, proceed to Phase 5.

---

## Phase 5: Update Experiment and Dataset Modules

### Overview

Update `Braintrust.Experiment.insert/3` and `Braintrust.Dataset.insert/3` to accept both raw maps and `%Braintrust.Span{}` structs, providing a consistent API across all insert functions.

### Changes Required

#### 1. Update Experiment Module

**File**: `lib/braintrust/experiment.ex`

Update the `insert/3` function to normalize events (convert Span structs to maps):

```elixir
# Add Span alias at the top of the module (around line 47)
alias Braintrust.{Client, Error, Span}

# Update the @spec and implementation (around line 318-324)
@spec insert(String.t(), [map() | Span.t()], keyword()) :: {:ok, map()} | {:error, Error.t()}
def insert(experiment_id, events, opts \\ []) when is_list(events) do
  client = Client.new(opts)
  normalized_events = Enum.map(events, &normalize_event/1)
  body = %{events: normalized_events}

  Client.post(client, "#{@api_path}/#{experiment_id}/insert", body)
end

# Add private helper function (at end of module, before to_struct/1)
defp normalize_event(%Span{} = span), do: Span.to_map(span)
defp normalize_event(event) when is_map(event), do: event
```

Update the `@doc` for `insert/3` to document Span struct support:

```elixir
@doc """
Inserts experiment events.

Events are the core data structure for experiment results. Each event
represents a single evaluation with input, output, and optional scores.

## Parameters

  * `events` - List of event maps or `%Braintrust.Span{}` structs, each containing:
    * `:id` - Unique event ID (optional, auto-generated if not provided)
    * `:input` - Input data (recommended: OpenAI message format)
    * `:output` - Output/response from the task
    * `:expected` - Expected output for scoring (optional)
    * `:scores` - Map of score names to values (0-1 range)
    * `:metadata` - Custom metadata map
    * `:metrics` - Numeric metrics (e.g., latency_ms, token_count)

## Options

  * `:api_key` - Override API key for this request
  * `:base_url` - Override base URL for this request

## Examples

    # With raw maps
    iex> {:ok, result} = Braintrust.Experiment.insert("exp_123", [
    ...>   %{
    ...>     input: %{messages: [%{role: "user", content: "What is 2+2?"}]},
    ...>     output: "4",
    ...>     scores: %{accuracy: 1.0},
    ...>     metadata: %{model: "gpt-4"}
    ...>   }
    ...> ])

    # With Span structs
    iex> spans = [%Braintrust.Span{input: %{q: "test"}, output: "result"}]
    iex> {:ok, result} = Braintrust.Experiment.insert("exp_123", spans)

"""
```

#### 2. Update Dataset Module

**File**: `lib/braintrust/dataset.ex`

Update the `insert/3` function similarly:

```elixir
# Add Span alias at the top of the module (with other aliases)
alias Braintrust.{Client, Error, Span}

# Update the @spec and implementation
@spec insert(String.t(), [map() | Span.t()], keyword()) :: {:ok, map()} | {:error, Error.t()}
def insert(dataset_id, records, opts \\ []) when is_list(records) do
  client = Client.new(opts)
  normalized_records = Enum.map(records, &normalize_record/1)
  body = %{events: normalized_records}

  Client.post(client, "#{@api_path}/#{dataset_id}/insert", body)
end

# Add private helper function (at end of module, before to_struct/1)
defp normalize_record(%Span{} = span), do: Span.to_map(span)
defp normalize_record(record) when is_map(record), do: record
```

Update the `@doc` for `insert/3` to document Span struct support:

```elixir
@doc """
Inserts dataset records.

Records represent test cases with input data and optional expected outputs.
Every insert is versioned via `_xact_id` for reproducibility.

## Parameters

  * `records` - List of record maps or `%Braintrust.Span{}` structs, each containing:
    * `:input` - Input data to recreate the example (required)
    * `:expected` - Expected output for scoring (optional)
    * `:metadata` - Custom metadata map (optional)
    * `:id` - Unique record ID (optional, auto-generated if not provided)

## Options

  * `:api_key` - Override API key for this request
  * `:base_url` - Override base URL for this request

## Examples

    # With raw maps
    iex> {:ok, result} = Braintrust.Dataset.insert("ds_123", [
    ...>   %{
    ...>     input: %{question: "What is 2+2?"},
    ...>     expected: "4"
    ...>   },
    ...>   %{
    ...>     input: %{question: "What is the capital of France?"},
    ...>     expected: "Paris",
    ...>     metadata: %{category: "geography"}
    ...>   }
    ...> ])

    # With Span structs
    iex> spans = [%Braintrust.Span{input: %{q: "test"}, expected: "answer"}]
    iex> {:ok, result} = Braintrust.Dataset.insert("ds_123", spans)

"""
```

#### 3. Add Tests for Span Support in Experiment

**File**: `test/braintrust/experiment_test.exs`

Add test cases for Span struct support:

```elixir
# Add in the describe "insert/3" block

test "inserts events with Span structs" do
  spans = [
    %Braintrust.Span{
      input: %{messages: [%{role: "user", content: "Hello"}]},
      output: "Hi there!",
      scores: %{quality: 0.9}
    }
  ]

  expect(Req, :request, fn _client, opts ->
    assert opts[:method] == :post
    assert opts[:url] == "/v1/experiment/exp_123/insert"

    # Span should be converted to map with nil values removed
    [event] = opts[:json][:events]
    assert event[:input] == %{messages: [%{role: "user", content: "Hello"}]}
    assert event[:output] == "Hi there!"
    assert event[:scores] == %{quality: 0.9}
    refute Map.has_key?(event, :id)
    refute Map.has_key?(event, :metadata)

    {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
  end)

  assert {:ok, result} = Experiment.insert("exp_123", spans)
  assert result["row_ids"] == ["row_1"]
end

test "inserts mixed events (maps and Span structs)" do
  events = [
    %{input: %{q: "map"}, output: "map result"},
    %Braintrust.Span{input: %{q: "span"}, output: "span result"}
  ]

  expect(Req, :request, fn _client, opts ->
    [event1, event2] = opts[:json][:events]

    # Map event unchanged
    assert event1 == %{input: %{q: "map"}, output: "map result"}

    # Span converted to map
    assert event2[:input] == %{q: "span"}
    assert event2[:output] == "span result"

    {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1", "row_2"]}, headers: []}}
  end)

  assert {:ok, result} = Experiment.insert("exp_123", events)
  assert length(result["row_ids"]) == 2
end
```

#### 4. Add Tests for Span Support in Dataset

**File**: `test/braintrust/dataset_test.exs`

Add test cases for Span struct support:

```elixir
# Add in the describe "insert/3" block

test "inserts records with Span structs" do
  spans = [
    %Braintrust.Span{
      input: %{question: "What is 2+2?"},
      expected: "4"
    }
  ]

  expect(Req, :request, fn _client, opts ->
    assert opts[:method] == :post
    assert opts[:url] == "/v1/dataset/ds_123/insert"

    # Span should be converted to map with nil values removed
    [record] = opts[:json][:events]
    assert record[:input] == %{question: "What is 2+2?"}
    assert record[:expected] == "4"
    refute Map.has_key?(record, :id)

    {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
  end)

  assert {:ok, result} = Dataset.insert("ds_123", spans)
  assert result["row_ids"] == ["row_1"]
end

test "inserts mixed records (maps and Span structs)" do
  records = [
    %{input: %{q: "map"}, expected: "map answer"},
    %Braintrust.Span{input: %{q: "span"}, expected: "span answer"}
  ]

  expect(Req, :request, fn _client, opts ->
    [record1, record2] = opts[:json][:events]

    # Map record unchanged
    assert record1 == %{input: %{q: "map"}, expected: "map answer"}

    # Span converted to map
    assert record2[:input] == %{q: "span"}
    assert record2[:expected] == "span answer"

    {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1", "row_2"]}, headers: []}}
  end)

  assert {:ok, result} = Dataset.insert("ds_123", records)
  assert length(result["row_ids"]) == 2
end
```

### Success Criteria

#### Automated Verification
- [x] All modules compile: `mix compile`
- [x] All quality checks pass: `mix quality` (Credo design suggestion for test duplication is acceptable)
- [x] All tests pass: `mix test` (161 tests, all passing)

#### Manual Verification
- [x] `Experiment.insert/3` accepts both maps and Span structs
- [x] `Dataset.insert/3` accepts both maps and Span structs
- [x] Backward compatibility maintained (existing code using maps still works)
- [x] Documentation updated to show Span struct examples

**Implementation Note**: After completing this phase and all automated verification passes, the implementation is complete.

---

## Testing Strategy

### Unit Tests

**Span Module**:
- Struct creation with all fields
- Struct creation with minimal fields
- `to_map/1` removes nil values
- `to_map/1` preserves all non-nil values
- `to_map/1` handles span_parents list

**Log Module**:
- `insert/3` with raw maps
- `insert/3` with Span structs
- `insert/3` with mixed inputs (maps and Spans)
- `insert/3` with metadata and metrics
- `insert/3` with batch events
- Guard clause validation (project_id must be string, events must be list)
- Error handling (server error, not found, unauthorized)
- Options override (api_key, base_url)
- Empty events list
- Events with error field

**Experiment Module (additions)**:
- `insert/3` with Span structs
- `insert/3` with mixed inputs (maps and Spans)

**Dataset Module (additions)**:
- `insert/3` with Span structs
- `insert/3` with mixed inputs (maps and Spans)

### Manual Testing Steps

1. Start IEx session: `iex -S mix`
2. Configure API key: `Braintrust.configure(api_key: "sk-...")`
3. Create a Span: `span = %Braintrust.Span{input: %{q: "test"}, output: "result"}`
4. **Log module:**
   - Test insert with map: `Braintrust.Log.insert("proj_id", [%{input: %{q: "test"}, output: "result"}])`
   - Test insert with Span: `Braintrust.Log.insert("proj_id", [span])`
   - Verify logs appear in Braintrust UI
5. **Experiment module:**
   - Test insert with Span: `Braintrust.Experiment.insert("exp_id", [span])`
   - Verify backward compatibility with maps still works
6. **Dataset module:**
   - Test insert with Span: `Braintrust.Dataset.insert("ds_id", [span])`
   - Verify backward compatibility with maps still works

## Performance Considerations

- `insert/3` accepts a list for batch submission, reducing HTTP overhead
- No streaming/pagination needed (write-only API)
- Future enhancement: async/buffered insert for high-volume logging

## Migration Notes

N/A - This is a new module with no existing data to migrate.

## References

- Source document: GitHub issue #15
- Related research: `thoughts/shared/research/braintrust_hex_package.md` (lines 324-373, 517-573)
- Similar implementation: `lib/braintrust/experiment.ex:318-324` (insert pattern)
- Test patterns: `test/braintrust/experiment_test.exs`
- Braintrust docs:
  - [Write Logs Guide](https://www.braintrust.dev/docs/guides/logs/write)
  - [Customize Traces](https://www.braintrust.dev/docs/guides/traces/customize)
  - [Span Interface](https://www.braintrust.dev/docs/reference/libs/nodejs/interfaces/Span)
