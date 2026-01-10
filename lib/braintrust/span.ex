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
