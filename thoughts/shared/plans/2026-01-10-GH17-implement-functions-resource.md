# Implement Functions Resource - Implementation Plan

## Overview

Implement the `Braintrust.Function` resource module for managing tools, scorers, and callable functions within Braintrust. Functions are versatile components that can be invoked by LLMs (tools), used for scoring evaluations (scorers), or serve as versioned prompts.

This implementation follows the established patterns from `Braintrust.Prompt` (lib/braintrust/prompt.ex:1-360), which is the closest existing implementation since prompts are a subset of functions in the Braintrust API.

## Current State Analysis

### Existing Resource Pattern (from Braintrust.Prompt)
- Module defines struct with `@type t` and `defstruct` (prompt.ex:73-108)
- CRUD operations: `list/1`, `stream/1`, `get/2`, `create/2`, `update/3`, `delete/2`
- All functions return `{:ok, result}` or `{:error, %Braintrust.Error{}}`
- Uses `Braintrust.Resource` module for shared helpers (resource.ex:1-79)
- Comprehensive doctests in `@doc` blocks
- Private `to_struct/1` function for API response conversion
- DateTime parsing for timestamp fields

### Key Differences: Function vs Prompt
1. **function_type field**: Functions have explicit types (`tool`, `scorer`, `prompt`)
2. **function_data field**: Polymorphic structure that varies by function type
3. **origin field**: Additional field for source tracking
4. **No messages/tools/tool_choice fields**: These are in function_data for prompt-type functions

### Key Discoveries
- Functions API endpoint: `/v1/function` (research doc line 412-418)
- Function types: `tool`, `scorer`, `prompt` (issue body)
- The `function_data` field is polymorphic based on function type
- Prompts are a subset of functions (accessible via both APIs)

## Desired End State

After implementation:
1. `Braintrust.Function` module exists at `lib/braintrust/function.ex`
2. `%Braintrust.Function{}` struct with all fields from the issue specification
3. Full CRUD operations: `list/1`, `stream/1`, `get/2`, `create/2`, `update/3`, `delete/2`
4. All operations return `{:ok, result}` or `{:error, %Braintrust.Error{}}`
5. Filtering support for `function_type` and `project_id` in list operations
6. Pagination via existing `Braintrust.Pagination` infrastructure
7. Doctests for all public functions
8. Comprehensive unit tests with mocked HTTP responses

### Verification
- All tests pass: `mix test test/braintrust/function_test.exs`
- Quality checks pass: `mix quality --quick`
- Doctests render correctly: `mix docs`

## What We're NOT Doing

1. **Function invocation/execution** - This plan only covers CRUD operations, not calling functions
2. **Streaming responses** - Not implementing function streaming in this iteration
3. **Scorer execution** - Not implementing evaluation scoring functionality
4. **LangChain integration** - That's a separate feature (mentioned in research doc)
5. **OpenTelemetry integration** - Separate feature for observability

## Implementation Approach

Follow the exact patterns established in `Braintrust.Prompt`:
1. Create `lib/braintrust/function.ex` with struct and CRUD functions
2. Add `function_name` filter parameter to `Braintrust.Resource.build_filter_params/2`
3. Create comprehensive tests at `test/braintrust/function_test.exs`

---

## Phase 1: Create Function Module with Struct and Types

### Overview
Create the `Braintrust.Function` module with the struct definition, type specifications, and module documentation.

### Changes Required

#### 1. Create Function Module
**File**: `lib/braintrust/function.ex` (new file)
**Changes**: Create module with struct, types, and documentation

```elixir
defmodule Braintrust.Function do
  @moduledoc """
  Manage Braintrust functions.

  Functions are versatile components that can serve as:
  - **Tools**: General purpose code invoked by LLMs for function calling
  - **Scorers**: Functions for scoring LLM output quality (0-1 range)
  - **Prompts**: Versioned prompt templates (also accessible via `Braintrust.Prompt`)

  ## Examples

      # List all functions
      {:ok, functions} = Braintrust.Function.list()

      # List scorers for a specific project
      {:ok, scorers} = Braintrust.Function.list(
        project_id: "proj_xxx",
        function_type: "scorer"
      )

      # Get a function by ID
      {:ok, func} = Braintrust.Function.get("func_xxx")

      # Create a code-based scorer
      {:ok, scorer} = Braintrust.Function.create(%{
        project_id: "proj_xxx",
        name: "relevance-scorer",
        slug: "relevance-scorer-v1",
        function_type: "scorer",
        function_data: %{
          type: "code",
          data: %{
            runtime: "node",
            code: "export default async function({ input, output, expected }) { ... }"
          }
        }
      })

      # Update a function
      {:ok, func} = Braintrust.Function.update("func_xxx", %{
        description: "Updated description"
      })

      # Delete a function
      {:ok, func} = Braintrust.Function.delete("func_xxx")

  ## Function Types

  | Type | Description | Use Case |
  |------|-------------|----------|
  | `tool` | General purpose code | Function calling, API integrations |
  | `scorer` | Quality scoring (0-1) | Evaluation metrics |
  | `prompt` | Versioned prompts | Also via `Braintrust.Prompt` |

  ## Scorer Subtypes

  Scorers can be implemented in different ways:

  - **Code-based**: TypeScript/Python scorers (fast, deterministic)
  - **LLM-as-a-judge**: Uses LLM to evaluate output (nuanced, subjective)
  - **Pre-built autoevals**: From autoevals library (ExactMatch, Levenshtein, etc.)

  ## Pagination

  The `list/1` function supports cursor-based pagination:

      # Get all functions as a list
      {:ok, functions} = Braintrust.Function.list()

      # Stream through functions lazily
      Braintrust.Function.stream()
      |> Stream.take(100)
      |> Enum.to_list()

  """

  alias Braintrust.{Client, Error}

  @type t :: %__MODULE__{
          id: String.t(),
          org_id: String.t() | nil,
          project_id: String.t() | nil,
          name: String.t(),
          slug: String.t() | nil,
          description: String.t() | nil,
          function_type: String.t() | nil,
          function_data: map() | nil,
          origin: map() | nil,
          user_id: String.t() | nil,
          metadata: map() | nil,
          created_at: DateTime.t() | nil,
          deleted_at: DateTime.t() | nil
        }

  # Note: API returns "created" but we use :created_at for Elixir naming consistency
  defstruct [
    :id,
    :org_id,
    :project_id,
    :name,
    :slug,
    :description,
    :function_type,
    :function_data,
    :origin,
    :user_id,
    :metadata,
    :created_at,
    :deleted_at
  ]

  @api_path "/v1/function"

  # ... CRUD functions will be added in Phase 2
end
```

### Success Criteria

#### Automated Verification
- [x] Module compiles without errors: `mix compile`
- [x] Code formatting passes: `mix format --check-formatted`

#### Manual Verification
- [x] Struct can be created in IEx: `%Braintrust.Function{id: "test", name: "test"}`

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: Implement CRUD Operations

### Overview
Add all CRUD operations following the patterns from `Braintrust.Prompt`.

### Changes Required

#### 1. Add list/1 and stream/1 Functions
**File**: `lib/braintrust/function.ex`
**Changes**: Add list and stream functions

```elixir
  @doc """
  Lists all functions.

  Returns all functions as a list. For large result sets, consider using
  `stream/1` for memory-efficient lazy loading.

  ## Options

    * `:limit` - Number of results per page (default: 100)
    * `:starting_after` - Cursor for pagination
    * `:project_id` - Filter by project ID
    * `:function_name` - Filter by function name
    * `:function_type` - Filter by type: "tool", "scorer", or "prompt"
    * `:slug` - Filter by function slug
    * `:org_name` - Filter by organization name
    * `:ids` - Filter by specific function IDs (list of strings)
    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, functions} = Braintrust.Function.list(limit: 10)
      iex> is_list(functions)
      true

  """
  @spec list(keyword()) :: {:ok, [t()]} | {:error, Error.t()}
  def list(opts \\ []) do
    Braintrust.Resource.list_all(@api_path, opts, &to_struct/1)
  end

  @doc """
  Returns a Stream that lazily paginates through all functions.

  This is memory-efficient for large result sets as it only fetches
  pages as items are consumed.

  ## Options

  Same as `list/1`.

  ## Examples

      # Take first 50 functions
      Braintrust.Function.stream(limit: 25)
      |> Stream.take(50)
      |> Enum.to_list()

      # Process all functions without loading all into memory
      Braintrust.Function.stream()
      |> Stream.each(&process_function/1)
      |> Stream.run()

  """
  @spec stream(keyword()) :: Enumerable.t()
  def stream(opts \\ []) do
    Braintrust.Resource.stream_all(@api_path, opts, &to_struct/1)
  end
```

#### 2. Add get/2 Function
**File**: `lib/braintrust/function.ex`
**Changes**: Add get function

```elixir
  @doc """
  Gets a function by ID.

  ## Options

    * `:version` - Specific version identifier to retrieve
    * `:xact_id` - Transaction ID for exact version
    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, func} = Braintrust.Function.get("func_123")
      iex> func.name
      "my-scorer"

      # Get a specific version
      iex> {:ok, func} = Braintrust.Function.get("func_123", version: "v2")

  """
  @spec get(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def get(function_id, opts \\ []) do
    {client_opts, query_opts} = Braintrust.Resource.split_opts(opts)
    client = Client.new(client_opts)

    params =
      []
      |> Braintrust.Resource.maybe_add(:version, query_opts[:version])
      |> Braintrust.Resource.maybe_add(:xact_id, query_opts[:xact_id])

    request_opts = if params == [], do: [], else: [params: params]

    case Client.get(client, "#{@api_path}/#{function_id}", request_opts) do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end
```

#### 3. Add create/2 Function
**File**: `lib/braintrust/function.ex`
**Changes**: Add create function

```elixir
  @doc """
  Creates a new function.

  If a function with the same name/slug already exists within the project,
  returns the existing function unmodified (idempotent behavior).

  ## Parameters

    * `:project_id` - Project ID (required)
    * `:name` - Function name (required)
    * `:slug` - Unique identifier for stable references (optional)
    * `:description` - Function description (optional)
    * `:function_type` - Type: "tool", "scorer", or "prompt" (optional)
    * `:function_data` - Function implementation data (optional)
    * `:origin` - Source tracking information (optional)
    * `:metadata` - Custom metadata map (optional)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      # Create a code-based scorer
      iex> {:ok, scorer} = Braintrust.Function.create(%{
      ...>   project_id: "proj_123",
      ...>   name: "relevance-scorer",
      ...>   slug: "relevance-scorer-v1",
      ...>   function_type: "scorer",
      ...>   function_data: %{
      ...>     type: "code",
      ...>     data: %{runtime: "node", code: "..."}
      ...>   }
      ...> })
      iex> scorer.function_type
      "scorer"

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
**File**: `lib/braintrust/function.ex`
**Changes**: Add update function

```elixir
  @doc """
  Updates a function.

  Uses PATCH semantics - only provided fields are updated. Updating a function
  may create a new version; previous versions remain accessible via version/xact_id.

  ## Parameters

    * `:name` - New function name
    * `:slug` - New slug identifier
    * `:description` - New description
    * `:function_type` - New function type
    * `:function_data` - Updated implementation data
    * `:metadata` - Metadata to merge (deep merge for nested objects)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, func} = Braintrust.Function.update("func_123", %{
      ...>   description: "Updated description"
      ...> })
      iex> func.description
      "Updated description"

  """
  @spec update(String.t(), map(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def update(function_id, params, opts \\ []) do
    client = Client.new(opts)

    case Client.patch(client, "#{@api_path}/#{function_id}", params) do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end
```

#### 5. Add delete/2 Function
**File**: `lib/braintrust/function.ex`
**Changes**: Add delete function

```elixir
  @doc """
  Deletes a function.

  This is a soft delete - the function's `deleted_at` field will be set.

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, func} = Braintrust.Function.delete("func_123")
      iex> func.deleted_at != nil
      true

  """
  @spec delete(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def delete(function_id, opts \\ []) do
    client = Client.new(opts)

    case Client.delete(client, "#{@api_path}/#{function_id}") do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end
```

#### 6. Add Private Helper Functions
**File**: `lib/braintrust/function.ex`
**Changes**: Add to_struct and parse_datetime

```elixir
  # Private Functions

  # Converts API response map to struct.
  # Note: Maps API field "created" to struct field :created_at for Elixir naming consistency.
  defp to_struct(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      org_id: map["org_id"],
      project_id: map["project_id"],
      name: map["name"],
      slug: map["slug"],
      description: map["description"],
      function_type: map["function_type"],
      function_data: map["function_data"],
      origin: map["origin"],
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

#### 7. Update Resource Module for function_name Filter
**File**: `lib/braintrust/resource.ex`
**Changes**: Add `function_name` and `function_type` to build_filter_params

```elixir
  # In build_filter_params/2, add these lines after the existing filters:
  |> maybe_add(:function_name, filter_params[:function_name])
  |> maybe_add(:function_type, filter_params[:function_type])
  # And in the second group for all_opts:
  |> maybe_add(:function_name, all_opts[:function_name])
  |> maybe_add(:function_type, all_opts[:function_type])
```

### Success Criteria

#### Automated Verification
- [x] Module compiles: `mix compile`
- [x] All quality checks pass: `mix quality --quick`

#### Manual Verification
- [x] Can call functions in IEx with mocked client

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 3: Create Comprehensive Tests

### Overview
Create test file with comprehensive coverage for all CRUD operations, following patterns from `test/braintrust/prompt_test.exs`.

### Changes Required

#### 1. Create Function Test File
**File**: `test/braintrust/function_test.exs` (new file)
**Changes**: Create comprehensive test suite

```elixir
defmodule Braintrust.FunctionTest do
  use ExUnit.Case, async: true
  use Mimic

  import Braintrust.TestHelpers

  alias Braintrust.{Config, Error, Function}

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
    test "returns list of function structs" do
      response = %{
        "objects" => [
          %{
            "id" => "func_1",
            "name" => "scorer-1",
            "project_id" => "proj_1",
            "function_type" => "scorer"
          },
          %{
            "id" => "func_2",
            "name" => "tool-1",
            "project_id" => "proj_1",
            "function_type" => "tool"
          }
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      assert {:ok, functions} = Function.list()
      assert length(functions) == 2
      assert [%Function{id: "func_1"}, %Function{id: "func_2"}] = functions

      Agent.stop(agent)
    end

    test "passes filter parameters" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            assert opts[:params][:project_id] == "proj_123"
            assert opts[:params][:function_type] == "scorer"
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      assert {:ok, []} = Function.list(project_id: "proj_123", function_type: "scorer")

      Agent.stop(agent)
    end

    test "returns error on failure" do
      stub(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Function.list()
    end
  end

  describe "stream/1" do
    test "returns a stream of function structs" do
      response = %{
        "objects" => [
          %{"id" => "func_1", "name" => "f1", "project_id" => "proj_1", "function_type" => "tool"}
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      functions = Function.stream() |> Enum.to_list()
      assert [%Function{id: "func_1"}] = functions

      Agent.stop(agent)
    end
  end

  describe "get/2" do
    test "returns function struct on success" do
      response = %{
        "id" => "func_123",
        "name" => "my-scorer",
        "project_id" => "proj_1",
        "slug" => "my-scorer-v1",
        "function_type" => "scorer",
        "function_data" => %{
          "type" => "code",
          "data" => %{"runtime" => "node", "code" => "..."}
        },
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/function/func_123"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.get("func_123")
      assert %Function{id: "func_123", name: "my-scorer"} = func
      assert func.function_type == "scorer"
      assert func.function_data["type"] == "code"
      assert %DateTime{} = func.created_at
    end

    test "supports version parameter" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:version] == "v2"

        {:ok,
         %Req.Response{status: 200, body: %{"id" => "func_123", "name" => "test"}, headers: []}}
      end)

      assert {:ok, _func} = Function.get("func_123", version: "v2")
    end

    test "supports xact_id parameter" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:xact_id] == "xact_abc123"

        {:ok,
         %Req.Response{status: 200, body: %{"id" => "func_123", "name" => "test"}, headers: []}}
      end)

      assert {:ok, _func} = Function.get("func_123", xact_id: "xact_abc123")
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Function not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Function.get("invalid")
    end
  end

  describe "create/2" do
    test "creates and returns function struct" do
      response = %{
        "id" => "func_new",
        "project_id" => "proj_123",
        "name" => "new-scorer",
        "slug" => "new-scorer-v1",
        "function_type" => "scorer"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:json][:name] == "new-scorer"
        assert opts[:json][:project_id] == "proj_123"
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, func} =
               Function.create(%{
                 project_id: "proj_123",
                 name: "new-scorer",
                 slug: "new-scorer-v1",
                 function_type: "scorer"
               })

      assert %Function{id: "func_new", name: "new-scorer"} = func
    end

    test "creates function with function_data" do
      function_data = %{
        type: "code",
        data: %{runtime: "node", code: "export default async function() { return 1.0; }"}
      }

      response = %{
        "id" => "func_new",
        "project_id" => "proj_123",
        "name" => "code-scorer",
        "function_type" => "scorer",
        "function_data" => function_data
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:json][:function_data] == function_data
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, func} =
               Function.create(%{
                 project_id: "proj_123",
                 name: "code-scorer",
                 function_type: "scorer",
                 function_data: function_data
               })

      assert func.function_data["type"] == "code"
    end

    test "returns existing function if name exists (idempotent)" do
      response = %{
        "id" => "func_existing",
        "project_id" => "proj_123",
        "name" => "existing-func"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} =
               Function.create(%{
                 project_id: "proj_123",
                 name: "existing-func"
               })

      assert func.id == "func_existing"
    end

    test "returns error on validation failure" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 400,
           body: %{"error" => %{"message" => "project_id is required"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :bad_request, message: "project_id is required"}} =
               Function.create(%{name: "test"})
    end
  end

  describe "update/3" do
    test "updates and returns function struct" do
      response = %{
        "id" => "func_123",
        "project_id" => "proj_1",
        "name" => "scorer",
        "description" => "Updated description"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json] == %{description: "Updated description"}
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.update("func_123", %{description: "Updated description"})
      assert func.description == "Updated description"
    end

    test "updates function_data" do
      new_function_data = %{
        type: "llm",
        data: %{model: "gpt-4", messages: [%{role: "system", content: "Rate quality..."}]}
      }

      response = %{
        "id" => "func_123",
        "project_id" => "proj_1",
        "name" => "scorer",
        "function_data" => new_function_data
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json][:function_data] == new_function_data
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.update("func_123", %{function_data: new_function_data})
      assert func.function_data["type"] == "llm"
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Function not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Function.update("invalid", %{name: "new-name"})
    end
  end

  describe "delete/2" do
    test "deletes and returns function with deleted_at set" do
      response = %{
        "id" => "func_123",
        "project_id" => "proj_1",
        "name" => "deleted-func",
        "deleted_at" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.delete("func_123")
      assert %DateTime{} = func.deleted_at
    end

    test "returns error on permission denied" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 403,
           body: %{"error" => %{"message" => "Permission denied"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :permission_denied}} = Function.delete("func_123")
    end
  end

  describe "to_struct/1 (via public functions)" do
    test "parses all fields correctly" do
      response = %{
        "id" => "func_1",
        "org_id" => "org_1",
        "project_id" => "proj_1",
        "name" => "test-function",
        "slug" => "test-function-v1",
        "description" => "Test description",
        "function_type" => "scorer",
        "function_data" => %{"type" => "code", "data" => %{}},
        "origin" => %{"type" => "api"},
        "user_id" => "user_1",
        "metadata" => %{"key" => "value"},
        "created" => "2024-01-15T14:15:22Z",
        "deleted_at" => nil
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.get("func_1")
      assert func.id == "func_1"
      assert func.org_id == "org_1"
      assert func.project_id == "proj_1"
      assert func.name == "test-function"
      assert func.slug == "test-function-v1"
      assert func.description == "Test description"
      assert func.function_type == "scorer"
      assert func.function_data == %{"type" => "code", "data" => %{}}
      assert func.origin == %{"type" => "api"}
      assert func.user_id == "user_1"
      assert func.metadata == %{"key" => "value"}
      assert %DateTime{year: 2024, month: 1, day: 15} = func.created_at
      assert func.deleted_at == nil
    end

    test "handles missing optional fields" do
      response = %{
        "id" => "func_1",
        "name" => "test"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.get("func_1")
      assert func.project_id == nil
      assert func.slug == nil
      assert func.function_type == nil
      assert func.function_data == nil
      assert func.origin == nil
      assert func.created_at == nil
    end

    test "handles invalid datetime strings" do
      response = %{
        "id" => "func_1",
        "name" => "test",
        "created" => "invalid-date"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.get("func_1")
      assert func.created_at == nil
    end

    test "maps 'created' API field to 'created_at' struct field" do
      response = %{
        "id" => "func_1",
        "name" => "test",
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, func} = Function.get("func_1")
      # Verify that the 'created' field from API is mapped to created_at in struct
      assert %DateTime{} = func.created_at
      assert func.created_at.year == 2024
    end
  end
end
```

### Success Criteria

#### Automated Verification
- [x] All tests pass: `mix test test/braintrust/function_test.exs`
- [x] Full test suite passes: `mix test`
- [x] All quality checks pass: `mix quality --quick`

#### Manual Verification
- [x] Test coverage looks complete for CRUD operations
- [x] Test patterns match existing resource tests

**Implementation Note**: After completing this phase and all automated verification passes, the implementation is complete.

---

## Testing Strategy

### Unit Tests (in test/braintrust/function_test.exs)
- All CRUD operations: list, stream, get, create, update, delete
- Filter parameters for list operations (project_id, function_type)
- Version and xact_id parameters for get
- Error handling for all operations
- Struct field parsing including function_data

### Doctests
- All public functions have doctests in their `@doc` blocks
- Doctests verify basic usage patterns

### Key Edge Cases
- Empty function_data handling
- Missing optional fields
- Invalid datetime strings
- Polymorphic function_data structures

## References

- Source issue: GitHub issue #17
- Pattern reference: `lib/braintrust/prompt.ex:1-360`
- Test pattern reference: `test/braintrust/prompt_test.exs:1-437`
- Resource helpers: `lib/braintrust/resource.ex:1-79`
- API documentation: `thoughts/shared/research/braintrust_hex_package.md:408-435`
