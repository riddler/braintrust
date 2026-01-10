# Implement Experiments Resource - Implementation Plan

## Overview

Implement the `Braintrust.Experiment` resource module with full CRUD operations and experiment-specific endpoints for managing AI evaluation experiments. This follows the established patterns from `Braintrust.Project` and provides idiomatic Elixir interfaces to the Experiments API.

## Current State Analysis

### Existing Infrastructure

The codebase already has the foundational modules needed:

- **`Braintrust.Project`** (`lib/braintrust/project.ex:1-300`) - Reference implementation for resource modules
- **`Braintrust.Client`** (`lib/braintrust/client.ex:1-323`) - HTTP client with retry logic, all HTTP methods
- **`Braintrust.Pagination`** (`lib/braintrust/pagination.ex:1-183`) - Cursor-based pagination with Stream support
- **`Braintrust.Error`** (`lib/braintrust/error.ex`) - Consistent error handling
- **`Braintrust.Config`** (`lib/braintrust/config.ex`) - Configuration management

### Patterns to Follow

From `Braintrust.Project`:
- Struct definition with `@type t` and `defstruct` at module top
- Private `to_struct/1` helper for API response → struct conversion
- Private `split_opts/1` to separate client opts from query opts
- Private `split_pagination_opts/1` and `build_filter_params/1` for query building
- All functions return `{:ok, result}` or `{:error, %Braintrust.Error{}}`
- Doctests in `@doc` blocks for usage examples

## Desired End State

After implementation:

1. `Braintrust.Experiment` module exists with:
   - `%Braintrust.Experiment{}` struct with all API fields
   - CRUD operations: `list/1`, `stream/1`, `get/2`, `create/2`, `update/3`, `delete/2`
   - Experiment-specific: `insert/3`, `fetch/3`, `fetch_stream/3`, `feedback/3`, `summarize/2`

2. Comprehensive test coverage in `test/braintrust/experiment_test.exs`

3. Updated documentation in `lib/braintrust.ex`, `README.md`, and `CHANGELOG.md`

### Verification

- All quality checks pass: `mix quality`
- Documentation generates without warnings: `mix docs`
- All tests pass: `mix test`

## What We're NOT Doing

- **Not creating a `Braintrust.Span` module** - Events/spans will use raw maps for now; `Braintrust.Span` will be introduced later with LangChain/OTLP integration
- **Not implementing comparison features** - While the API supports `base_exp_id` and comparison in summarize, we're not adding specialized comparison helpers
- **Not implementing batch operations** - Single insert/feedback calls only; batching can be added later

## Implementation Approach

Follow the exact patterns established in `Braintrust.Project`, extending with experiment-specific operations. Use raw maps for event data to keep the initial implementation simple and flexible.

---

## Phase 1: Core Module with CRUD Operations

### Overview

Create the `Braintrust.Experiment` module with struct definition and standard CRUD operations, mirroring the `Braintrust.Project` implementation.

### Changes Required

#### 1. Create Experiment Module

**File**: `lib/braintrust/experiment.ex`

```elixir
defmodule Braintrust.Experiment do
  @moduledoc """
  Manage Braintrust experiments.

  Experiments are containers for evaluation runs that track AI model performance
  against datasets and scoring functions.

  ## Examples

      # List all experiments
      {:ok, experiments} = Braintrust.Experiment.list()

      # List experiments for a specific project
      {:ok, experiments} = Braintrust.Experiment.list(project_id: "proj_123")

      # Create an experiment
      {:ok, experiment} = Braintrust.Experiment.create(%{
        project_id: "proj_123",
        name: "baseline-v1"
      })

      # Get an experiment by ID
      {:ok, experiment} = Braintrust.Experiment.get("exp_123")

      # Update an experiment
      {:ok, experiment} = Braintrust.Experiment.update("exp_123", %{
        description: "Updated description"
      })

      # Delete an experiment
      {:ok, experiment} = Braintrust.Experiment.delete("exp_123")

  ## Pagination

  The `list/1` function supports cursor-based pagination:

      # Get all experiments as a list
      {:ok, experiments} = Braintrust.Experiment.list()

      # Stream through experiments lazily
      Braintrust.Experiment.stream()
      |> Stream.take(100)
      |> Enum.to_list()

  """

  alias Braintrust.{Client, Error}

  @type t :: %__MODULE__{
          id: String.t(),
          project_id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          repo_info: map() | nil,
          base_exp_id: String.t() | nil,
          dataset_id: String.t() | nil,
          dataset_version: String.t() | nil,
          public: boolean(),
          user_id: String.t() | nil,
          metadata: map() | nil,
          created_at: DateTime.t() | nil,
          deleted_at: DateTime.t() | nil
        }

  defstruct [
    :id,
    :project_id,
    :name,
    :description,
    :repo_info,
    :base_exp_id,
    :dataset_id,
    :dataset_version,
    :public,
    :user_id,
    :metadata,
    :created_at,
    :deleted_at
  ]

  @api_path "/v1/experiment"

  @doc """
  Lists all experiments.

  Returns all experiments as a list. For large result sets, consider using
  `stream/1` for memory-efficient lazy loading.

  ## Options

    * `:limit` - Number of results per page (default: 100)
    * `:starting_after` - Cursor for pagination
    * `:project_id` - Filter by project ID
    * `:experiment_name` - Filter by experiment name
    * `:org_name` - Filter by organization name
    * `:ids` - Filter by specific experiment IDs (list of strings)
    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, experiments} = Braintrust.Experiment.list(limit: 10)
      iex> is_list(experiments)
      true

  """
  @spec list(keyword()) :: {:ok, [t()]} | {:error, Error.t()}
  def list(opts \\ []) do
    {client_opts, query_opts} = split_opts(opts)
    client = Client.new(client_opts)
    {pagination_opts, filter_params} = split_pagination_opts(query_opts)
    params = build_filter_params(filter_params)

    get_all_opts = Keyword.merge(pagination_opts, params: params)

    case Client.get_all(client, @api_path, get_all_opts) do
      {:ok, items} -> {:ok, Enum.map(items, &to_struct/1)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Returns a Stream that lazily paginates through all experiments.

  This is memory-efficient for large result sets as it only fetches
  pages as items are consumed.

  ## Options

  Same as `list/1`.

  ## Examples

      # Take first 50 experiments
      Braintrust.Experiment.stream(limit: 25)
      |> Stream.take(50)
      |> Enum.to_list()

      # Process all experiments without loading all into memory
      Braintrust.Experiment.stream()
      |> Stream.each(&process_experiment/1)
      |> Stream.run()

  """
  @spec stream(keyword()) :: Enumerable.t()
  def stream(opts \\ []) do
    {client_opts, query_opts} = split_opts(opts)
    client = Client.new(client_opts)
    {pagination_opts, filter_params} = split_pagination_opts(query_opts)
    params = build_filter_params(filter_params)

    get_stream_opts = Keyword.merge(pagination_opts, params: params)

    client
    |> Client.get_stream(@api_path, get_stream_opts)
    |> Stream.map(&to_struct/1)
  end

  @doc """
  Gets an experiment by ID.

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, experiment} = Braintrust.Experiment.get("exp_123")
      iex> experiment.name
      "baseline-v1"

  """
  @spec get(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def get(experiment_id, opts \\ []) do
    client = Client.new(opts)

    case Client.get(client, "#{@api_path}/#{experiment_id}") do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Creates a new experiment.

  If an experiment with the same name already exists within the project,
  returns the existing experiment unmodified (idempotent behavior).

  ## Parameters

    * `:project_id` - Project ID (required)
    * `:name` - Experiment name (required for idempotent creation)
    * `:description` - Experiment description (optional)
    * `:repo_info` - Git repository info map (optional)
    * `:base_exp_id` - Base experiment ID for comparisons (optional)
    * `:dataset_id` - Linked dataset ID (optional)
    * `:dataset_version` - Dataset version/transaction ID (optional)
    * `:public` - Public visibility flag (optional)
    * `:metadata` - Custom metadata map (optional)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, experiment} = Braintrust.Experiment.create(%{
      ...>   project_id: "proj_123",
      ...>   name: "baseline-v1"
      ...> })
      iex> experiment.name
      "baseline-v1"

      # With metadata and dataset
      iex> {:ok, experiment} = Braintrust.Experiment.create(%{
      ...>   project_id: "proj_123",
      ...>   name: "eval-run-1",
      ...>   dataset_id: "ds_456",
      ...>   metadata: %{model: "gpt-4", temperature: 0.7}
      ...> })

  """
  @spec create(map(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def create(params, opts \\ []) do
    client = Client.new(opts)

    case Client.post(client, @api_path, params) do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Updates an experiment.

  Uses PATCH semantics - only provided fields are updated. Object fields
  like `metadata` support deep merge.

  ## Parameters

    * `:name` - New experiment name
    * `:description` - New description
    * `:metadata` - Metadata to merge (deep merge for nested objects)
    * `:public` - Update visibility

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, experiment} = Braintrust.Experiment.update("exp_123", %{
      ...>   description: "Updated description"
      ...> })
      iex> experiment.description
      "Updated description"

  """
  @spec update(String.t(), map(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def update(experiment_id, params, opts \\ []) do
    client = Client.new(opts)

    case Client.patch(client, "#{@api_path}/#{experiment_id}", params) do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Deletes an experiment.

  This is a soft delete - the experiment's `deleted_at` field will be set.

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, experiment} = Braintrust.Experiment.delete("exp_123")
      iex> experiment.deleted_at != nil
      true

  """
  @spec delete(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def delete(experiment_id, opts \\ []) do
    client = Client.new(opts)

    case Client.delete(client, "#{@api_path}/#{experiment_id}") do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end

  # Private Functions

  defp split_opts(opts) do
    Keyword.split(opts, [:api_key, :base_url, :timeout, :max_retries])
  end

  defp split_pagination_opts(opts) do
    Keyword.split(opts, [:limit, :starting_after, :ending_before])
  end

  defp build_filter_params(opts) do
    []
    |> maybe_add(:project_id, opts[:project_id])
    |> maybe_add(:experiment_name, opts[:experiment_name])
    |> maybe_add(:org_name, opts[:org_name])
    |> maybe_add(:ids, opts[:ids])
  end

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, value), do: Keyword.put(params, key, value)

  defp to_struct(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      project_id: map["project_id"],
      name: map["name"],
      description: map["description"],
      repo_info: map["repo_info"],
      base_exp_id: map["base_exp_id"],
      dataset_id: map["dataset_id"],
      dataset_version: map["dataset_version"],
      public: map["public"] || false,
      user_id: map["user_id"],
      metadata: map["metadata"],
      created_at: parse_datetime(map["created"]),
      deleted_at: parse_datetime(map["deleted_at"])
    }
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      {:error, _reason} -> nil
    end
  end
end
```

### Success Criteria

#### Automated Verification:
- [x] Code compiles: `mix compile`
- [x] Code formatting passes: `mix format --check-formatted`
- [x] Credo passes: `mix credo --strict`

#### Manual Verification:
- [x] Module structure matches `Braintrust.Project` patterns
- [x] All CRUD functions have proper `@doc`, `@spec` annotations

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to the next phase.

---

## Phase 2: Experiment-Specific Operations

### Overview

Add the experiment-specific operations for inserting events, fetching events, adding feedback, and getting summaries.

### Changes Required

#### 1. Add Experiment-Specific Functions

**File**: `lib/braintrust/experiment.ex`

Add the following functions after the `delete/2` function:

```elixir
  # =============================================================================
  # Experiment-Specific Operations
  # =============================================================================

  @doc """
  Inserts experiment events.

  Events are the core data structure for experiment results. Each event
  represents a single evaluation with input, output, and optional scores.

  ## Parameters

    * `events` - List of event maps, each containing:
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

      iex> {:ok, result} = Braintrust.Experiment.insert("exp_123", [
      ...>   %{
      ...>     input: %{messages: [%{role: "user", content: "What is 2+2?"}]},
      ...>     output: "4",
      ...>     scores: %{accuracy: 1.0},
      ...>     metadata: %{model: "gpt-4"}
      ...>   }
      ...> ])

  """
  @spec insert(String.t(), [map()], keyword()) :: {:ok, map()} | {:error, Error.t()}
  def insert(experiment_id, events, opts \\ []) when is_list(events) do
    client = Client.new(opts)
    body = %{events: events}

    Client.post(client, "#{@api_path}/#{experiment_id}/insert", body)
  end

  @doc """
  Fetches experiment events.

  Returns a single page of events. For iterating through all events,
  use `fetch_stream/3`.

  ## Parameters

    * `:limit` - Number of events to return (default: 100)
    * `:cursor` - Pagination cursor from previous response
    * `:max_xact_id` - Maximum transaction ID to fetch up to
    * `:max_root_span_id` - Maximum root span ID to fetch up to
    * `:filters` - List of filter objects for querying events
    * `:version` - Dataset version to fetch (specific transaction ID)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, result} = Braintrust.Experiment.fetch("exp_123", limit: 50)
      iex> is_list(result["events"])
      true

  """
  @spec fetch(String.t(), keyword(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def fetch(experiment_id, params \\ [], opts \\ []) do
    client = Client.new(opts)
    body = Map.new(params)

    Client.post(client, "#{@api_path}/#{experiment_id}/fetch", body)
  end

  @doc """
  Returns a Stream that lazily paginates through experiment events.

  This is memory-efficient for large result sets as it only fetches
  pages as items are consumed.

  ## Parameters

  Same as `fetch/3`.

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      # Stream through all events
      Braintrust.Experiment.fetch_stream("exp_123")
      |> Stream.each(&process_event/1)
      |> Stream.run()

      # Take first 100 events
      Braintrust.Experiment.fetch_stream("exp_123", limit: 50)
      |> Stream.take(100)
      |> Enum.to_list()

  """
  @spec fetch_stream(String.t(), keyword(), keyword()) :: Enumerable.t()
  def fetch_stream(experiment_id, params \\ [], opts \\ []) do
    client = Client.new(opts)
    initial_params = Map.new(params)

    Stream.resource(
      fn -> fetch_events_page(client, experiment_id, initial_params) end,
      &next_event(client, experiment_id, initial_params, &1),
      fn _state -> :ok end
    )
  end

  @doc """
  Logs feedback on experiment events.

  Use this to add scores, comments, or corrections to existing events
  after they've been inserted.

  ## Parameters

    * `feedback` - List of feedback maps, each containing:
      * `:id` - Event ID to attach feedback to (required)
      * `:scores` - Map of score names to values (0-1 range)
      * `:expected` - Expected output (correction)
      * `:comment` - Text comment
      * `:metadata` - Additional metadata
      * `:source` - Feedback source (e.g., "app", "human", "api")

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, result} = Braintrust.Experiment.feedback("exp_123", [
      ...>   %{
      ...>     id: "event_456",
      ...>     scores: %{human_rating: 0.8},
      ...>     comment: "Good response but could be more concise"
      ...>   }
      ...> ])

  """
  @spec feedback(String.t(), [map()], keyword()) :: {:ok, map()} | {:error, Error.t()}
  def feedback(experiment_id, feedback, opts \\ []) when is_list(feedback) do
    client = Client.new(opts)
    body = %{feedback: feedback}

    Client.post(client, "#{@api_path}/#{experiment_id}/feedback", body)
  end

  @doc """
  Gets a summary of experiment results.

  Returns aggregated metrics and scores for the experiment, optionally
  compared against another experiment.

  ## Parameters

    * `:summarize_scores` - Whether to include score summaries (default: true)
    * `:comparison_experiment_id` - Experiment ID to compare against

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, summary} = Braintrust.Experiment.summarize("exp_123")
      iex> is_list(summary["scores"])
      true

      # Compare against baseline
      iex> {:ok, summary} = Braintrust.Experiment.summarize("exp_123",
      ...>   comparison_experiment_id: "exp_baseline"
      ...> )

  """
  @spec summarize(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def summarize(experiment_id, opts \\ []) do
    {client_opts, query_opts} = split_opts(opts)
    client = Client.new(client_opts)

    params =
      []
      |> maybe_add(:summarize_scores, query_opts[:summarize_scores])
      |> maybe_add(:comparison_experiment_id, query_opts[:comparison_experiment_id])

    Client.get(client, "#{@api_path}/#{experiment_id}/summarize", params: params)
  end

  # Private helpers for fetch_stream

  defp fetch_events_page(client, experiment_id, params) do
    body = params

    case Client.post(client, "#{@api_path}/#{experiment_id}/fetch", body) do
      {:ok, %{"events" => events, "cursor" => cursor}} when is_list(events) and events != [] ->
        {events, cursor}

      {:ok, %{"events" => events}} when is_list(events) and events != [] ->
        {events, nil}

      {:ok, _response} ->
        {[], nil}

      {:error, error} ->
        throw({:fetch_error, error})
    end
  end

  defp next_event(_client, _experiment_id, _params, {[], nil}) do
    {:halt, nil}
  end

  defp next_event(client, experiment_id, params, {[], cursor}) when not is_nil(cursor) do
    params_with_cursor = Map.put(params, :cursor, cursor)

    case fetch_events_page(client, experiment_id, params_with_cursor) do
      {[], nil} ->
        {:halt, nil}

      {events, new_cursor} ->
        [head | tail] = events
        {[head], {tail, new_cursor}}
    end
  end

  defp next_event(_client, _experiment_id, _params, {[event | rest], cursor}) do
    {[event], {rest, cursor}}
  end
```

### Success Criteria

#### Automated Verification:
- [x] Code compiles: `mix compile`
- [x] Code formatting passes: `mix format --check-formatted`
- [x] Credo passes: `mix credo --strict`

#### Manual Verification:
- [x] All experiment-specific functions have proper `@doc`, `@spec` annotations
- [x] `fetch_stream/3` follows Stream.resource pattern correctly

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to the next phase.

---

## Phase 3: Test Suite

### Overview

Create comprehensive tests for all Experiment functions, using Mimic for HTTP mocking (same pattern as `project_test.exs`).

### Changes Required

#### 1. Create Experiment Test File

**File**: `test/braintrust/experiment_test.exs`

```elixir
defmodule Braintrust.ExperimentTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Braintrust.{Config, Error, Experiment}

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

  describe "list/1" do
    test "returns list of experiment structs" do
      response = %{
        "objects" => [
          %{
            "id" => "exp_1",
            "project_id" => "proj_1",
            "name" => "experiment-1",
            "public" => false
          },
          %{
            "id" => "exp_2",
            "project_id" => "proj_1",
            "name" => "experiment-2",
            "public" => true
          }
        ]
      }

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      stub(Req, :request, fn _client, _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok, %Req.Response{status: 200, body: response, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      assert {:ok, experiments} = Experiment.list()
      assert length(experiments) == 2
      assert [%Experiment{id: "exp_1"}, %Experiment{id: "exp_2"}] = experiments

      Agent.stop(agent)
    end

    test "passes filter parameters" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            assert opts[:params][:project_id] == "proj_123"
            assert opts[:params][:experiment_name] == "test"
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      assert {:ok, []} = Experiment.list(project_id: "proj_123", experiment_name: "test")

      Agent.stop(agent)
    end

    test "returns error on failure" do
      stub(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Experiment.list()
    end
  end

  describe "stream/1" do
    test "returns a stream of experiment structs" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      stub(Req, :request, fn _client, _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{
                 "objects" => [
                   %{"id" => "exp_1", "project_id" => "proj_1", "name" => "e1", "public" => false}
                 ]
               },
               headers: []
             }}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      experiments = Experiment.stream() |> Enum.to_list()
      assert [%Experiment{id: "exp_1"}] = experiments

      Agent.stop(agent)
    end
  end

  describe "get/2" do
    test "returns experiment struct on success" do
      response = %{
        "id" => "exp_123",
        "project_id" => "proj_1",
        "name" => "my-experiment",
        "description" => "Test experiment",
        "public" => false,
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/experiment/exp_123"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} = Experiment.get("exp_123")
      assert %Experiment{id: "exp_123", name: "my-experiment"} = experiment
      assert %DateTime{} = experiment.created_at
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Experiment not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Experiment.get("invalid")
    end
  end

  describe "create/2" do
    test "creates and returns experiment struct" do
      response = %{
        "id" => "exp_new",
        "project_id" => "proj_123",
        "name" => "new-experiment",
        "public" => false
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:json] == %{project_id: "proj_123", name: "new-experiment"}
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, experiment} =
               Experiment.create(%{project_id: "proj_123", name: "new-experiment"})

      assert %Experiment{id: "exp_new", name: "new-experiment"} = experiment
    end

    test "returns existing experiment if name exists (idempotent)" do
      response = %{
        "id" => "exp_existing",
        "project_id" => "proj_123",
        "name" => "existing-experiment",
        "public" => false
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} =
               Experiment.create(%{project_id: "proj_123", name: "existing-experiment"})

      assert experiment.id == "exp_existing"
    end
  end

  describe "update/3" do
    test "updates and returns experiment struct" do
      response = %{
        "id" => "exp_123",
        "project_id" => "proj_1",
        "name" => "experiment",
        "description" => "Updated description",
        "public" => false
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json] == %{description: "Updated description"}
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} =
               Experiment.update("exp_123", %{description: "Updated description"})

      assert experiment.description == "Updated description"
    end
  end

  describe "delete/2" do
    test "deletes and returns experiment with deleted_at set" do
      response = %{
        "id" => "exp_123",
        "project_id" => "proj_1",
        "name" => "deleted-experiment",
        "public" => false,
        "deleted_at" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} = Experiment.delete("exp_123")
      assert %DateTime{} = experiment.deleted_at
    end
  end

  describe "insert/3" do
    test "inserts events and returns result" do
      events = [
        %{
          input: %{messages: [%{role: "user", content: "Hello"}]},
          output: "Hi there!",
          scores: %{quality: 0.9}
        }
      ]

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/experiment/exp_123/insert"
        assert opts[:json] == %{events: events}
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
      end)

      assert {:ok, result} = Experiment.insert("exp_123", events)
      assert result["row_ids"] == ["row_1"]
    end
  end

  describe "fetch/3" do
    test "fetches events with pagination" do
      response = %{
        "events" => [
          %{"id" => "evt_1", "input" => %{}, "output" => "response"}
        ],
        "cursor" => "next_cursor"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/experiment/exp_123/fetch"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, result} = Experiment.fetch("exp_123", limit: 50)
      assert length(result["events"]) == 1
      assert result["cursor"] == "next_cursor"
    end
  end

  describe "fetch_stream/3" do
    test "streams through events across pages" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{
                 "events" => [%{"id" => "evt_1"}, %{"id" => "evt_2"}],
                 "cursor" => "cursor_1"
               },
               headers: []
             }}

          1 ->
            assert opts[:json][:cursor] == "cursor_1"

            {:ok,
             %Req.Response{
               status: 200,
               body: %{"events" => [%{"id" => "evt_3"}]},
               headers: []
             }}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"events" => []}, headers: []}}
        end
      end)

      events = Experiment.fetch_stream("exp_123") |> Enum.to_list()
      assert length(events) == 3
      assert [%{"id" => "evt_1"}, %{"id" => "evt_2"}, %{"id" => "evt_3"}] = events

      Agent.stop(agent)
    end
  end

  describe "feedback/3" do
    test "submits feedback for events" do
      feedback = [
        %{
          id: "evt_123",
          scores: %{human_rating: 0.8},
          comment: "Good response"
        }
      ]

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/experiment/exp_123/feedback"
        assert opts[:json] == %{feedback: feedback}
        {:ok, %Req.Response{status: 200, body: %{}, headers: []}}
      end)

      assert {:ok, _result} = Experiment.feedback("exp_123", feedback)
    end
  end

  describe "summarize/2" do
    test "returns experiment summary" do
      response = %{
        "project_name" => "my-project",
        "experiment_name" => "my-experiment",
        "scores" => [
          %{"name" => "accuracy", "score" => 0.85}
        ],
        "metrics" => [
          %{"name" => "latency", "metric" => 250, "unit" => "ms"}
        ]
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/experiment/exp_123/summarize"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, summary} = Experiment.summarize("exp_123")
      assert summary["experiment_name"] == "my-experiment"
      assert length(summary["scores"]) == 1
    end

    test "supports comparison experiment" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:comparison_experiment_id] == "exp_baseline"
        {:ok, %Req.Response{status: 200, body: %{"scores" => []}, headers: []}}
      end)

      assert {:ok, _summary} =
               Experiment.summarize("exp_123", comparison_experiment_id: "exp_baseline")
    end
  end

  describe "to_struct/1 (via public functions)" do
    test "parses all fields correctly" do
      response = %{
        "id" => "exp_1",
        "project_id" => "proj_1",
        "name" => "test",
        "description" => "Test description",
        "repo_info" => %{"branch" => "main", "commit" => "abc123"},
        "base_exp_id" => "exp_base",
        "dataset_id" => "ds_1",
        "dataset_version" => "v1",
        "public" => true,
        "user_id" => "user_1",
        "metadata" => %{"key" => "value"},
        "created" => "2024-01-15T14:15:22Z",
        "deleted_at" => nil
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} = Experiment.get("exp_1")
      assert experiment.id == "exp_1"
      assert experiment.project_id == "proj_1"
      assert experiment.description == "Test description"
      assert experiment.repo_info == %{"branch" => "main", "commit" => "abc123"}
      assert experiment.base_exp_id == "exp_base"
      assert experiment.dataset_id == "ds_1"
      assert experiment.dataset_version == "v1"
      assert experiment.public == true
      assert experiment.user_id == "user_1"
      assert experiment.metadata == %{"key" => "value"}
      assert %DateTime{year: 2024, month: 1, day: 15} = experiment.created_at
      assert experiment.deleted_at == nil
    end

    test "handles missing optional fields" do
      response = %{
        "id" => "exp_1",
        "project_id" => "proj_1",
        "name" => "test"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, experiment} = Experiment.get("exp_1")
      assert experiment.description == nil
      assert experiment.repo_info == nil
      assert experiment.public == false
      assert experiment.metadata == nil
    end
  end
end
```

### Success Criteria

#### Automated Verification:
- [x] All tests pass: `mix test test/braintrust/experiment_test.exs`
- [x] All quality checks pass: `mix quality`

#### Manual Verification:
- [ ] Test coverage is comprehensive for all public functions
- [ ] Test patterns match `project_test.exs` style

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to the next phase.

---

## Phase 4: Documentation Updates

### Overview

Update documentation in the main module, README, and CHANGELOG.

### Changes Required

#### 1. Update Main Module

**File**: `lib/braintrust.ex`

Update the moduledoc to include Experiments:

```elixir
  @moduledoc """
  Unofficial Elixir SDK for the [Braintrust](https://braintrust.dev) AI evaluation and observability platform.

  ## Installation

  Add `braintrust` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:braintrust, "~> 0.1.0"}
        ]
      end

  ## Configuration

  Set your API key via environment variable:

      export BRAINTRUST_API_KEY="sk-your-api-key"

  Or configure in your application:

      # config/config.exs
      config :braintrust,
        api_key: System.get_env("BRAINTRUST_API_KEY"),
        timeout: 30_000

  Or configure at runtime:

      Braintrust.configure(api_key: "sk-your-api-key")

  ## Usage

  See the individual resource modules for API operations:

  - `Braintrust.Project` - Manage projects
  - `Braintrust.Experiment` - Run evaluations and track results
  - `Braintrust.Dataset` - Manage datasets (coming soon)
  - `Braintrust.Log` - Log traces and spans (coming soon)

  ## Resources

  - [Braintrust Documentation](https://www.braintrust.dev/docs)
  - [API Reference](https://www.braintrust.dev/docs/api-reference/introduction)
  - [GitHub Repository](https://github.com/riddler/braintrust)
  """
```

#### 2. Update README

**File**: `README.md`

Add Experiments section after Projects examples:

```markdown
### Experiments

Run evaluations and track experiment results:

```elixir
# Create an experiment
{:ok, experiment} = Braintrust.Experiment.create(%{
  project_id: "proj_123",
  name: "gpt4-baseline"
})

# Insert evaluation events
{:ok, _} = Braintrust.Experiment.insert(experiment.id, [
  %{
    input: %{messages: [%{role: "user", content: "What is 2+2?"}]},
    output: "4",
    expected: "4",
    scores: %{accuracy: 1.0},
    metadata: %{model: "gpt-4"}
  }
])

# Get experiment summary
{:ok, summary} = Braintrust.Experiment.summarize(experiment.id)

# Stream through all events
Braintrust.Experiment.fetch_stream(experiment.id)
|> Stream.each(&process_event/1)
|> Stream.run()

# Add feedback to events
{:ok, _} = Braintrust.Experiment.feedback(experiment.id, [
  %{id: "event_123", scores: %{human_rating: 0.9}, comment: "Good response"}
])
```
```

#### 3. Update CHANGELOG

**File**: `CHANGELOG.md`

Add entry for new version:

```markdown
## [Unreleased]

### Added

- `Braintrust.Experiment` module with full CRUD operations
  - `list/1`, `stream/1` - List experiments with pagination
  - `get/2` - Get experiment by ID
  - `create/2` - Create new experiment
  - `update/3` - Update experiment
  - `delete/2` - Delete experiment (soft delete)
- Experiment-specific operations
  - `insert/3` - Insert evaluation events
  - `fetch/3`, `fetch_stream/3` - Fetch events with pagination
  - `feedback/3` - Add scores and comments to events
  - `summarize/2` - Get aggregated experiment metrics
```

### Success Criteria

#### Automated Verification:
- [x] Documentation generates without warnings: `mix docs`
- [x] All quality checks pass: `mix quality`

#### Manual Verification:
- [x] README examples are accurate and complete
- [x] CHANGELOG follows existing format
- [x] Module documentation is clear and helpful

**Implementation Note**: After completing this phase and all automated verification passes, the implementation is complete.

---

## Testing Strategy

### Unit Tests

All tests use Mimic to mock HTTP responses:

- CRUD operations: test success, error handling, parameter passing
- Experiment-specific operations: test request format, response parsing
- Edge cases: empty responses, missing fields, pagination boundaries

### Manual Testing Steps

1. Configure real API key: `export BRAINTRUST_API_KEY="sk-..."`
2. Create a test project and experiment via IEx
3. Insert sample events and verify in Braintrust UI
4. Test pagination with `fetch_stream/3`
5. Test `summarize/2` to verify metrics aggregation

---

## Performance Considerations

- `fetch_stream/3` uses lazy evaluation to handle large event sets efficiently
- Pagination defaults to 100 items per page (configurable via `:limit`)
- No batching for `insert/3` - consider adding batch support later if needed

---

## References

- Source document: GitHub Issue #13
- Research: `thoughts/shared/research/braintrust_hex_package.md`
- Reference implementation: `lib/braintrust/project.ex`
- API docs: https://www.braintrust.dev/docs/reference/api/Experiments
