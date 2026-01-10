# Datasets Resource Implementation Plan

## Overview

Implement the `Braintrust.Dataset` resource module following the established patterns from `Braintrust.Project` and `Braintrust.Experiment`. Datasets are containers for test data used in AI evaluations, with built-in versioning via `_xact_id` for reproducibility.

## Current State Analysis

### Existing Patterns

The codebase has well-established patterns for resource modules:

- **Project module** (`lib/braintrust/project.ex:1-263`): CRUD-only resource with 7 struct fields
- **Experiment module** (`lib/braintrust/experiment.ex:1-554`): CRUD + data operations (insert, fetch, fetch_stream, feedback, summarize) with 12 struct fields

The Dataset module will be most similar to Experiment, as it requires both CRUD operations and data operations.

### Key Discoveries

1. **Shared helpers**: `Braintrust.Resource` module at `lib/braintrust/resource.ex:1-73` provides `list_all/3` and `stream_all/3` for consistent list/stream implementations
2. **Client methods**: HTTP client at `lib/braintrust/client.ex` provides `get/3`, `post/4`, `patch/4`, `delete/3`, `get_all/3`, `get_stream/3`
3. **Test patterns**: Tests use Mimic for mocking, with pagination agent helpers in `test/support/test_helpers.ex`
4. **Data operations**: Experiment module shows pattern for `insert/3`, `fetch/3`, `fetch_stream/3`, `feedback/3`, `summarize/2`

## Desired End State

A fully implemented `Braintrust.Dataset` module with:

1. Struct with all fields from the API specification
2. CRUD operations (list, stream, get, create, update, delete)
3. Data operations (insert, fetch, fetch_stream, feedback, summarize)
4. Comprehensive doctests for all public functions
5. Full test coverage with mocked HTTP responses
6. Integration with existing Resource and Pagination helpers

### Verification

- All quality checks pass: `mix quality`
- Doctests execute successfully: `mix test`
- Module follows established patterns (struct definition, function signatures, error handling)

## What We're NOT Doing

- **No new shared infrastructure**: Will reuse existing `Braintrust.Resource`, `Braintrust.Client`, `Braintrust.Pagination` modules
- **No OpenTelemetry integration**: Out of scope for this ticket
- **No LangChain integration**: Out of scope for this ticket
- **No async/batching optimizations**: Basic synchronous API only

## Implementation Approach

Follow the exact patterns from `Braintrust.Experiment` module since it has the same structure (CRUD + data operations). The Dataset module will be nearly identical in structure, with Dataset-specific fields and API paths.

---

## Phase 1: Dataset Module Structure

### Overview

Create the `Braintrust.Dataset` module with struct definition, type spec, and module constant.

### Changes Required

#### 1. Create Dataset Module

**File**: `lib/braintrust/dataset.ex`

```elixir
defmodule Braintrust.Dataset do
  @moduledoc """
  Manage Braintrust datasets.

  Datasets are containers for test data used in AI evaluations. Each dataset
  stores input/expected pairs that can be used to evaluate AI model performance.

  ## Examples

      # List all datasets
      {:ok, datasets} = Braintrust.Dataset.list()

      # List datasets for a specific project
      {:ok, datasets} = Braintrust.Dataset.list(project_id: "proj_123")

      # Create a dataset
      {:ok, dataset} = Braintrust.Dataset.create(%{
        project_id: "proj_123",
        name: "test-cases"
      })

      # Get a dataset by ID
      {:ok, dataset} = Braintrust.Dataset.get("ds_123")

      # Insert records
      {:ok, result} = Braintrust.Dataset.insert("ds_123", [
        %{input: %{question: "What is 2+2?"}, expected: "4"}
      ])

      # Delete a dataset
      {:ok, dataset} = Braintrust.Dataset.delete("ds_123")

  ## Pagination

  The `list/1` function supports cursor-based pagination:

      # Get all datasets as a list
      {:ok, datasets} = Braintrust.Dataset.list()

      # Stream through datasets lazily
      Braintrust.Dataset.stream()
      |> Stream.take(100)
      |> Enum.to_list()

  ## Versioning

  Every insert, update, and delete operation is versioned via `_xact_id`.
  Use the `fetch/3` function with a `:version` parameter to retrieve records
  at a specific dataset version for reproducible evaluations.

  """

  alias Braintrust.{Client, Error}

  @type t :: %__MODULE__{
          id: String.t(),
          project_id: String.t(),
          name: String.t(),
          description: String.t() | nil,
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
    :user_id,
    :metadata,
    :created_at,
    :deleted_at
  ]

  @api_path "/v1/dataset"

  # ... CRUD and data operations to be added
end
```

### Success Criteria

#### Automated Verification
- [x] Module compiles: `mix compile`
- [x] Code formatting passes: `mix format --check-formatted`

#### Manual Verification
- [x] Struct definition matches API specification from GitHub issue
- [x] Module documentation is comprehensive

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: CRUD Operations

### Overview

Implement the standard CRUD functions following the exact patterns from `Braintrust.Experiment`.

### Changes Required

#### 1. Add list/1 and stream/1 Functions

**File**: `lib/braintrust/dataset.ex`

Add after `@api_path`:

```elixir
  @doc """
  Lists all datasets.

  Returns all datasets as a list. For large result sets, consider using
  `stream/1` for memory-efficient lazy loading.

  ## Options

    * `:limit` - Number of results per page (default: 100)
    * `:starting_after` - Cursor for pagination
    * `:project_id` - Filter by project ID
    * `:dataset_name` - Filter by dataset name
    * `:org_name` - Filter by organization name
    * `:ids` - Filter by specific dataset IDs (list of strings)
    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, datasets} = Braintrust.Dataset.list(limit: 10)
      iex> is_list(datasets)
      true

  """
  @spec list(keyword()) :: {:ok, [t()]} | {:error, Error.t()}
  def list(opts \\ []) do
    Braintrust.Resource.list_all(@api_path, opts, &to_struct/1)
  end

  @doc """
  Returns a Stream that lazily paginates through all datasets.

  This is memory-efficient for large result sets as it only fetches
  pages as items are consumed.

  ## Options

  Same as `list/1`.

  ## Examples

      # Take first 50 datasets
      Braintrust.Dataset.stream(limit: 25)
      |> Stream.take(50)
      |> Enum.to_list()

      # Process all datasets without loading all into memory
      Braintrust.Dataset.stream()
      |> Stream.each(&process_dataset/1)
      |> Stream.run()

  """
  @spec stream(keyword()) :: Enumerable.t()
  def stream(opts \\ []) do
    Braintrust.Resource.stream_all(@api_path, opts, &to_struct/1)
  end
```

#### 2. Add get/2 Function

```elixir
  @doc """
  Gets a dataset by ID.

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, dataset} = Braintrust.Dataset.get("ds_123")
      iex> dataset.name
      "test-cases"

  """
  @spec get(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def get(dataset_id, opts \\ []) do
    client = Client.new(opts)

    case Client.get(client, "#{@api_path}/#{dataset_id}") do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end
```

#### 3. Add create/2 Function

```elixir
  @doc """
  Creates a new dataset.

  If a dataset with the same name already exists within the project,
  returns the existing dataset unmodified (idempotent behavior).

  ## Parameters

    * `:project_id` - Project ID (required)
    * `:name` - Dataset name (required for idempotent creation)
    * `:description` - Dataset description (optional)
    * `:metadata` - Custom metadata map (optional)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, dataset} = Braintrust.Dataset.create(%{
      ...>   project_id: "proj_123",
      ...>   name: "test-cases"
      ...> })
      iex> dataset.name
      "test-cases"

      # With description
      iex> {:ok, dataset} = Braintrust.Dataset.create(%{
      ...>   project_id: "proj_123",
      ...>   name: "evaluation-data",
      ...>   description: "Test cases for Q&A evaluation"
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
```

#### 4. Add update/3 Function

```elixir
  @doc """
  Updates a dataset.

  Uses PATCH semantics - only provided fields are updated. Object fields
  like `metadata` support deep merge.

  ## Parameters

    * `:name` - New dataset name
    * `:description` - New description
    * `:metadata` - Metadata to merge (deep merge for nested objects)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, dataset} = Braintrust.Dataset.update("ds_123", %{
      ...>   description: "Updated description"
      ...> })
      iex> dataset.description
      "Updated description"

  """
  @spec update(String.t(), map(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def update(dataset_id, params, opts \\ []) do
    client = Client.new(opts)

    case Client.patch(client, "#{@api_path}/#{dataset_id}", params) do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end
```

#### 5. Add delete/2 Function

```elixir
  @doc """
  Deletes a dataset.

  This is a soft delete - the dataset's `deleted_at` field will be set.

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, dataset} = Braintrust.Dataset.delete("ds_123")
      iex> dataset.deleted_at != nil
      true

  """
  @spec delete(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def delete(dataset_id, opts \\ []) do
    client = Client.new(opts)

    case Client.delete(client, "#{@api_path}/#{dataset_id}") do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end
```

#### 6. Add to_struct/1 and parse_datetime/1 Private Functions

```elixir
  # Private Functions

  defp to_struct(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      project_id: map["project_id"],
      name: map["name"],
      description: map["description"],
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
```

#### 7. Update Resource Module for Dataset Filters

**File**: `lib/braintrust/resource.ex`

Add `dataset_name` to the filter params at line 58:

```elixir
  @spec build_filter_params(keyword(), keyword()) :: keyword()
  def build_filter_params(filter_params, all_opts) do
    []
    |> maybe_add(:project_id, filter_params[:project_id])
    |> maybe_add(:project_name, filter_params[:project_name])
    |> maybe_add(:experiment_name, filter_params[:experiment_name])
    |> maybe_add(:dataset_name, filter_params[:dataset_name])
    |> maybe_add(:org_name, filter_params[:org_name])
    |> maybe_add(:ids, filter_params[:ids])
    # Support all possible filter keys from all_opts if not in filter_params
    |> maybe_add(:project_id, all_opts[:project_id])
    |> maybe_add(:project_name, all_opts[:project_name])
    |> maybe_add(:experiment_name, all_opts[:experiment_name])
    |> maybe_add(:dataset_name, all_opts[:dataset_name])
    |> maybe_add(:org_name, all_opts[:org_name])
    |> Enum.uniq_by(fn {key, _value} -> key end)
  end
```

### Success Criteria

#### Automated Verification
- [x] Module compiles: `mix compile`
- [x] Code formatting passes: `mix format --check-formatted`
- [x] Credo passes: `mix credo --strict`

#### Manual Verification
- [x] CRUD functions follow the exact pattern from Experiment module
- [x] Function signatures match the spec in GitHub issue

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 3: Data Operations

### Overview

Implement the data operations for datasets: `insert/3`, `fetch/3`, `fetch_stream/3`, `feedback/3`, and `summarize/2`.

### Changes Required

#### 1. Add Section Comment

**File**: `lib/braintrust/dataset.ex`

Add after delete/2 function:

```elixir
  # =============================================================================
  # Dataset-Specific Operations
  # =============================================================================
```

#### 2. Add insert/3 Function

```elixir
  @doc """
  Inserts dataset records.

  Records represent test cases with input data and optional expected outputs.
  Every insert is versioned via `_xact_id` for reproducibility.

  ## Parameters

    * `records` - List of record maps, each containing:
      * `:input` - Input data to recreate the example (required)
      * `:expected` - Expected output for scoring (optional)
      * `:metadata` - Custom metadata map (optional)
      * `:id` - Unique record ID (optional, auto-generated if not provided)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

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

  """
  @spec insert(String.t(), [map()], keyword()) :: {:ok, map()} | {:error, Error.t()}
  def insert(dataset_id, records, opts \\ []) when is_list(records) do
    client = Client.new(opts)
    body = %{events: records}

    Client.post(client, "#{@api_path}/#{dataset_id}/insert", body)
  end
```

#### 3. Add fetch/3 Function

```elixir
  @doc """
  Fetches dataset records.

  Returns a single page of records. For iterating through all records,
  use `fetch_stream/3`.

  ## Parameters

    * `:limit` - Number of records to return (default: 100)
    * `:cursor` - Pagination cursor from previous response
    * `:max_xact_id` - Maximum transaction ID to fetch up to
    * `:max_root_span_id` - Maximum root span ID to fetch up to
    * `:filters` - List of filter objects for querying records
    * `:version` - Dataset version to fetch (specific transaction ID)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, result} = Braintrust.Dataset.fetch("ds_123", limit: 50)
      iex> is_list(result["events"])
      true

  """
  @spec fetch(String.t(), keyword(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def fetch(dataset_id, params \\ [], opts \\ []) do
    client = Client.new(opts)
    body = Map.new(params)

    Client.post(client, "#{@api_path}/#{dataset_id}/fetch", body)
  end
```

#### 4. Add fetch_stream/3 Function

```elixir
  @doc """
  Returns a Stream that lazily paginates through dataset records.

  This is memory-efficient for large result sets as it only fetches
  pages as items are consumed.

  ## Parameters

  Same as `fetch/3`.

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      # Stream through all records
      Braintrust.Dataset.fetch_stream("ds_123")
      |> Stream.each(&process_record/1)
      |> Stream.run()

      # Take first 100 records
      Braintrust.Dataset.fetch_stream("ds_123", limit: 50)
      |> Stream.take(100)
      |> Enum.to_list()

  """
  @spec fetch_stream(String.t(), keyword(), keyword()) :: Enumerable.t()
  def fetch_stream(dataset_id, params \\ [], opts \\ []) do
    client = Client.new(opts)
    initial_params = Map.new(params)

    Stream.resource(
      fn -> fetch_records_page(client, dataset_id, initial_params) end,
      &next_record(client, dataset_id, initial_params, &1),
      fn _state -> :ok end
    )
  end
```

#### 5. Add feedback/3 Function

```elixir
  @doc """
  Logs feedback on dataset records.

  Use this to add scores, comments, or corrections to existing records
  after they've been inserted.

  ## Parameters

    * `feedback` - List of feedback maps, each containing:
      * `:id` - Record ID to attach feedback to (required)
      * `:scores` - Map of score names to values (0-1 range)
      * `:expected` - Expected output (correction)
      * `:comment` - Text comment
      * `:metadata` - Additional metadata
      * `:source` - Feedback source (e.g., "app", "human", "api")

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, result} = Braintrust.Dataset.feedback("ds_123", [
      ...>   %{
      ...>     id: "record_456",
      ...>     scores: %{quality: 0.9},
      ...>     comment: "High quality test case"
      ...>   }
      ...> ])

  """
  @spec feedback(String.t(), [map()], keyword()) :: {:ok, map()} | {:error, Error.t()}
  def feedback(dataset_id, feedback, opts \\ []) when is_list(feedback) do
    client = Client.new(opts)
    body = %{feedback: feedback}

    Client.post(client, "#{@api_path}/#{dataset_id}/feedback", body)
  end
```

#### 6. Add summarize/2 Function

```elixir
  @doc """
  Gets a summary of dataset contents.

  Returns aggregated statistics about the dataset.

  ## Parameters

    * `:summarize_data` - Whether to include data summaries (default: true)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, summary} = Braintrust.Dataset.summarize("ds_123")
      iex> is_binary(summary["project_name"])
      true

  """
  @spec summarize(String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def summarize(dataset_id, opts \\ []) do
    {client_opts, query_opts} = Braintrust.Resource.split_opts(opts)
    client = Client.new(client_opts)

    params =
      []
      |> Braintrust.Resource.maybe_add(:summarize_data, query_opts[:summarize_data])

    Client.get(client, "#{@api_path}/#{dataset_id}/summarize", params: params)
  end
```

#### 7. Add Private Helpers for fetch_stream

```elixir
  # Private helpers for fetch_stream

  defp fetch_records_page(client, dataset_id, params) do
    body = params

    case Client.post(client, "#{@api_path}/#{dataset_id}/fetch", body) do
      {:ok, %{"events" => records, "cursor" => cursor}} when is_list(records) and records != [] ->
        {records, cursor}

      {:ok, %{"events" => records}} when is_list(records) and records != [] ->
        {records, nil}

      {:ok, _response} ->
        {[], nil}

      {:error, error} ->
        throw({:fetch_error, error})
    end
  end

  defp next_record(_client, _dataset_id, _params, {[], nil}) do
    {:halt, nil}
  end

  defp next_record(client, dataset_id, params, {[], cursor}) when not is_nil(cursor) do
    params_with_cursor = Map.put(params, :cursor, cursor)

    case fetch_records_page(client, dataset_id, params_with_cursor) do
      {[], nil} ->
        {:halt, nil}

      {records, new_cursor} ->
        [head | tail] = records
        {[head], {tail, new_cursor}}
    end
  end

  defp next_record(_client, _dataset_id, _params, {[record | rest], cursor}) do
    {[record], {rest, cursor}}
  end
```

### Success Criteria

#### Automated Verification
- [x] Module compiles: `mix compile`
- [x] Code formatting passes: `mix format --check-formatted`
- [x] Credo passes: `mix credo --strict`

#### Manual Verification
- [x] Data operations follow the exact pattern from Experiment module
- [x] Function signatures match the spec in GitHub issue

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 4: Unit Tests

### Overview

Create comprehensive unit tests for all Dataset functions following the patterns from `test/braintrust/experiment_test.exs`.

### Changes Required

#### 1. Create Dataset Test File

**File**: `test/braintrust/dataset_test.exs`

```elixir
defmodule Braintrust.DatasetTest do
  use ExUnit.Case, async: true
  use Mimic

  import Braintrust.TestHelpers

  alias Braintrust.{Config, Error, Dataset}

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
    test "returns list of dataset structs" do
      response = %{
        "objects" => [
          %{
            "id" => "ds_1",
            "project_id" => "proj_1",
            "name" => "dataset-1"
          },
          %{
            "id" => "ds_2",
            "project_id" => "proj_1",
            "name" => "dataset-2"
          }
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      assert {:ok, datasets} = Dataset.list()
      assert length(datasets) == 2
      assert [%Dataset{id: "ds_1"}, %Dataset{id: "ds_2"}] = datasets

      Agent.stop(agent)
    end

    test "passes filter parameters" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            assert opts[:params][:project_id] == "proj_123"
            assert opts[:params][:dataset_name] == "test"
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      assert {:ok, []} = Dataset.list(project_id: "proj_123", dataset_name: "test")

      Agent.stop(agent)
    end

    test "returns error on failure" do
      stub(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Dataset.list()
    end
  end

  describe "stream/1" do
    test "returns a stream of dataset structs" do
      response = %{
        "objects" => [
          %{"id" => "ds_1", "project_id" => "proj_1", "name" => "d1"}
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      datasets = Dataset.stream() |> Enum.to_list()
      assert [%Dataset{id: "ds_1"}] = datasets

      Agent.stop(agent)
    end
  end

  describe "get/2" do
    test "returns dataset struct on success" do
      response = %{
        "id" => "ds_123",
        "project_id" => "proj_1",
        "name" => "my-dataset",
        "description" => "Test dataset",
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/dataset/ds_123"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.get("ds_123")
      assert %Dataset{id: "ds_123", name: "my-dataset"} = dataset
      assert %DateTime{} = dataset.created_at
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Dataset not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Dataset.get("invalid")
    end
  end

  describe "create/2" do
    test "creates and returns dataset struct" do
      response = %{
        "id" => "ds_new",
        "project_id" => "proj_123",
        "name" => "new-dataset"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:json] == %{project_id: "proj_123", name: "new-dataset"}
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.create(%{project_id: "proj_123", name: "new-dataset"})
      assert %Dataset{id: "ds_new", name: "new-dataset"} = dataset
    end

    test "returns existing dataset if name exists (idempotent)" do
      response = %{
        "id" => "ds_existing",
        "project_id" => "proj_123",
        "name" => "existing-dataset"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.create(%{project_id: "proj_123", name: "existing-dataset"})
      assert dataset.id == "ds_existing"
    end
  end

  describe "update/3" do
    test "updates and returns dataset struct" do
      response = %{
        "id" => "ds_123",
        "project_id" => "proj_1",
        "name" => "dataset",
        "description" => "Updated description"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json] == %{description: "Updated description"}
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.update("ds_123", %{description: "Updated description"})
      assert dataset.description == "Updated description"
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Dataset not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Dataset.update("ds_invalid", %{name: "new-name"})
    end
  end

  describe "delete/2" do
    test "deletes and returns dataset with deleted_at set" do
      response = %{
        "id" => "ds_123",
        "project_id" => "proj_1",
        "name" => "deleted-dataset",
        "deleted_at" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.delete("ds_123")
      assert %DateTime{} = dataset.deleted_at
    end
  end

  describe "insert/3" do
    test "inserts records and returns result" do
      records = [
        %{
          input: %{question: "What is 2+2?"},
          expected: "4"
        }
      ]

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/dataset/ds_123/insert"
        assert opts[:json] == %{events: records}
        {:ok, %Req.Response{status: 200, body: %{"row_ids" => ["row_1"]}, headers: []}}
      end)

      assert {:ok, result} = Dataset.insert("ds_123", records)
      assert result["row_ids"] == ["row_1"]
    end

    test "requires records to be a list" do
      assert_raise FunctionClauseError, fn ->
        Dataset.insert("ds_123", %{invalid: "not a list"})
      end
    end
  end

  describe "fetch/3" do
    test "fetches records with pagination" do
      response = %{
        "events" => [
          %{"id" => "rec_1", "input" => %{question: "test"}, "expected" => "answer"}
        ],
        "cursor" => "next_cursor"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/dataset/ds_123/fetch"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, result} = Dataset.fetch("ds_123", limit: 50)
      assert length(result["events"]) == 1
      assert result["cursor"] == "next_cursor"
    end
  end

  describe "fetch_stream/3" do
    test "streams through records across pages" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok,
             %Req.Response{
               status: 200,
               body: %{
                 "events" => [%{"id" => "rec_1"}, %{"id" => "rec_2"}],
                 "cursor" => "cursor_1"
               },
               headers: []
             }}

          1 ->
            assert opts[:json][:cursor] == "cursor_1"

            {:ok,
             %Req.Response{
               status: 200,
               body: %{"events" => [%{"id" => "rec_3"}]},
               headers: []
             }}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"events" => []}, headers: []}}
        end
      end)

      records = Dataset.fetch_stream("ds_123") |> Enum.to_list()
      assert length(records) == 3
      assert [%{"id" => "rec_1"}, %{"id" => "rec_2"}, %{"id" => "rec_3"}] = records

      Agent.stop(agent)
    end

    test "handles empty records list" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok, %Req.Response{status: 200, body: %{"events" => []}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"events" => []}, headers: []}}
        end
      end)

      records = Dataset.fetch_stream("ds_123") |> Enum.to_list()
      assert records == []

      Agent.stop(agent)
    end

    test "propagates fetch errors via throw" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"events" => []}, headers: []}}
        end
      end)

      assert catch_throw(Dataset.fetch_stream("ds_123") |> Enum.to_list()) ==
               {:fetch_error,
                %Braintrust.Error{
                  type: :server_error,
                  message: "Server error",
                  code: nil,
                  status: 500,
                  retry_after: nil
                }}

      Agent.stop(agent)
    end
  end

  describe "feedback/3" do
    test "submits feedback for records" do
      feedback = [
        %{
          id: "rec_123",
          scores: %{quality: 0.9},
          comment: "Good test case"
        }
      ]

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/dataset/ds_123/feedback"
        assert opts[:json] == %{feedback: feedback}
        {:ok, %Req.Response{status: 200, body: %{}, headers: []}}
      end)

      assert {:ok, _result} = Dataset.feedback("ds_123", feedback)
    end

    test "requires feedback to be a list" do
      assert_raise FunctionClauseError, fn ->
        Dataset.feedback("ds_123", %{invalid: "not a list"})
      end
    end
  end

  describe "summarize/2" do
    test "returns dataset summary" do
      response = %{
        "project_name" => "my-project",
        "dataset_name" => "my-dataset",
        "data_summary" => %{
          "total_records" => 100
        }
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/dataset/ds_123/summarize"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, summary} = Dataset.summarize("ds_123")
      assert summary["dataset_name"] == "my-dataset"
    end

    test "supports summarize_data option" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:summarize_data] == true
        {:ok, %Req.Response{status: 200, body: %{"data_summary" => %{}}, headers: []}}
      end)

      assert {:ok, _summary} = Dataset.summarize("ds_123", summarize_data: true)
    end
  end

  describe "to_struct/1 (via public functions)" do
    test "parses all fields correctly" do
      response = %{
        "id" => "ds_1",
        "project_id" => "proj_1",
        "name" => "test",
        "description" => "Test description",
        "user_id" => "user_1",
        "metadata" => %{"key" => "value"},
        "created" => "2024-01-15T14:15:22Z",
        "deleted_at" => nil
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.get("ds_1")
      assert dataset.id == "ds_1"
      assert dataset.project_id == "proj_1"
      assert dataset.description == "Test description"
      assert dataset.user_id == "user_1"
      assert dataset.metadata == %{"key" => "value"}
      assert %DateTime{year: 2024, month: 1, day: 15} = dataset.created_at
      assert dataset.deleted_at == nil
    end

    test "handles missing optional fields" do
      response = %{
        "id" => "ds_1",
        "project_id" => "proj_1",
        "name" => "test"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.get("ds_1")
      assert dataset.description == nil
      assert dataset.metadata == nil
      assert dataset.user_id == nil
    end

    test "handles invalid datetime strings" do
      response = %{
        "id" => "ds_1",
        "project_id" => "proj_1",
        "name" => "test",
        "created" => "invalid-date"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, dataset} = Dataset.get("ds_1")
      assert dataset.created_at == nil
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

## Phase 5: Integration and Documentation

### Overview

Finalize the implementation by ensuring all doctests work and updating any necessary exports.

### Changes Required

#### 1. Verify Doctests

Run `mix test` to ensure all doctests in the module documentation execute correctly. The doctests are embedded in the `@doc` blocks.

#### 2. Update Main Braintrust Module (if needed)

**File**: `lib/braintrust.ex`

If there's a main `Braintrust` module that re-exports functions, add Dataset:

```elixir
defdelegate list_datasets(opts \\ []), to: Braintrust.Dataset, as: :list
defdelegate get_dataset(id, opts \\ []), to: Braintrust.Dataset, as: :get
defdelegate create_dataset(params, opts \\ []), to: Braintrust.Dataset, as: :create
defdelegate update_dataset(id, params, opts \\ []), to: Braintrust.Dataset, as: :update
defdelegate delete_dataset(id, opts \\ []), to: Braintrust.Dataset, as: :delete
```

(Only add if the pattern exists for Project/Experiment)

### Success Criteria

#### Automated Verification
- [x] All quality checks pass: `mix quality` ✅ (All Credo issues resolved)
- [x] All tests pass: `mix test` ✅ (138 tests, 19 doctests)
- [x] Documentation generates correctly: `mix docs` ✅

#### Manual Verification
- [x] Module is accessible in IEx: `iex -S mix` then `Braintrust.Dataset.list()`
- [x] Documentation renders correctly in generated docs
- [x] No warnings during compilation

**Implementation Note**: After completing this phase and all automated verification passes, the implementation is complete.

---

## Testing Strategy

### Unit Tests

**CRUD Operations**:
- `list/1` - Test pagination, filters, error handling
- `stream/1` - Test lazy enumeration
- `get/2` - Test success, not found error
- `create/2` - Test success, idempotent behavior
- `update/3` - Test success, not found error
- `delete/2` - Test soft delete with `deleted_at`

**Data Operations**:
- `insert/3` - Test record insertion, list validation
- `fetch/3` - Test pagination parameters, cursor handling
- `fetch_stream/3` - Test multi-page streaming, empty results, error propagation
- `feedback/3` - Test feedback submission, list validation
- `summarize/2` - Test summary retrieval, options

**Struct Conversion**:
- All fields parsed correctly
- Missing optional fields handled
- Invalid datetime strings handled gracefully

### Manual Testing Steps

1. Start IEx session: `iex -S mix`
2. Configure API key: `Braintrust.configure(api_key: "sk-...")`
3. Test list: `Braintrust.Dataset.list()`
4. Test create: `Braintrust.Dataset.create(%{project_id: "...", name: "test"})`
5. Test get: `Braintrust.Dataset.get("ds_...")`
6. Test insert: `Braintrust.Dataset.insert("ds_...", [%{input: %{q: "test"}}])`
7. Test delete: `Braintrust.Dataset.delete("ds_...")`

## Performance Considerations

- `fetch_stream/3` uses lazy evaluation to avoid loading all records into memory
- Pagination is handled efficiently with cursor-based approach
- No additional performance optimizations needed for initial implementation

## Migration Notes

N/A - This is a new module with no existing data to migrate.

## References

- Source document: GitHub issue #14
- Related research: `thoughts/shared/research/braintrust_hex_package.md`
- Similar implementation: `lib/braintrust/experiment.ex:1-554`
- Test patterns: `test/braintrust/experiment_test.exs:1-596`
- GitHub issue: #14
