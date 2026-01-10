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
