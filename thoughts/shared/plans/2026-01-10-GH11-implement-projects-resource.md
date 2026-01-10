# Implement Projects Resource - Implementation Plan

## Overview

Implement the `Braintrust.Project` resource module to provide full CRUD operations for Braintrust projects. This is the first resource module, serving as a reference implementation that validates the HTTP client, pagination, and error handling patterns.

## Current State Analysis

The codebase has all necessary infrastructure in place:

- **HTTP Client** (`lib/braintrust/client.ex:1-323`): Full-featured client with `get/3`, `post/4`, `patch/4`, `delete/3`, plus pagination helpers `get_stream/3` and `get_all/3`
- **Pagination** (`lib/braintrust/pagination.ex:1-183`): Stream-based cursor pagination expecting `%{"objects" => [...]}` response format
- **Error Handling** (`lib/braintrust/error.ex:1-142`): `%Braintrust.Error{}` struct with type atoms matching HTTP status codes
- **Configuration** (`lib/braintrust/config.ex:1-211`): Multi-source config with precedence chain
- **Testing**: Uses `Mimic` library to mock `Req` module (`test/test_helper.exs:2`)

### Key Discoveries:
- Client returns raw maps from API, not structs (`lib/braintrust/client.ex:210-211`)
- Pagination uses `"id"` field from last item as cursor (`lib/braintrust/pagination.ex:160-164`)
- Tests configure API key via `Config.configure/1` in setup (`test/braintrust/client_test.exs:14`)
- All public functions should have doctests per CLAUDE.md guidelines

## Desired End State

A fully functional `Braintrust.Project` module that:

1. Defines `%Braintrust.Project{}` struct with all API fields
2. Provides CRUD operations: `list/1`, `create/1`, `get/2`, `update/2`, `delete/2`
3. Integrates with existing pagination for `list/1` with Stream support
4. Returns proper `{:ok, result}` / `{:error, %Braintrust.Error{}}` tuples
5. Has comprehensive doctests and tests
6. Passes `mix quality --quick`

### Verification:
```bash
# All quality checks pass
mix quality --quick

# Doctests work
mix test test/braintrust/project_test.exs

# Module is documented
mix docs && open doc/Braintrust.Project.html
```

## What We're NOT Doing

- Implementing other resources (Experiment, Dataset, etc.) - separate issues
- Adding OpenTelemetry integration
- Implementing batch operations
- Adding caching
- Creating integration tests against live API

## Implementation Approach

Create a single new file `lib/braintrust/project.ex` with the struct and all CRUD functions colocated. Add a corresponding test file that mocks `Req` using `Mimic`. Follow the patterns established in `Client` and `Error` modules for documentation style.

The key design decision is that **resource modules convert API response maps to structs**, providing a typed interface while the Client module remains generic.

---

## Phase 1: Project Struct & Type Definitions

### Overview
Define the `Braintrust.Project` struct with all fields from the API, type specifications, and module documentation.

### Changes Required:

#### 1. Create Project Module
**File**: `lib/braintrust/project.ex` (new)
**Changes**: Create module with struct definition and types

```elixir
defmodule Braintrust.Project do
  @moduledoc """
  Manage Braintrust projects.

  Projects are the foundational organizational unit in Braintrust - containers
  for experiments, datasets, and logs.

  ## Examples

      # List all projects
      {:ok, projects} = Braintrust.Project.list()

      # Create a project
      {:ok, project} = Braintrust.Project.create(%{name: "my-project"})

      # Get a project by ID
      {:ok, project} = Braintrust.Project.get("proj_123")

      # Update a project
      {:ok, project} = Braintrust.Project.update("proj_123", %{name: "new-name"})

      # Delete a project
      {:ok, project} = Braintrust.Project.delete("proj_123")

  ## Pagination

  The `list/1` function supports cursor-based pagination:

      # Get all projects as a list
      {:ok, projects} = Braintrust.Project.list()

      # Stream through projects lazily
      Braintrust.Project.stream()
      |> Stream.take(100)
      |> Enum.to_list()

  """

  alias Braintrust.{Client, Error}

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          org_id: String.t(),
          user_id: String.t() | nil,
          created_at: DateTime.t() | nil,
          deleted_at: DateTime.t() | nil,
          settings: map() | nil
        }

  defstruct [:id, :name, :org_id, :user_id, :created_at, :deleted_at, :settings]

  @api_path "/v1/project"
end
```

### Success Criteria:

#### Automated Verification:
- [x] Module compiles: `mix compile`
- [x] Code formatting passes: `mix format --check-formatted`

#### Manual Verification:
- [x] Struct can be created in IEx: `%Braintrust.Project{id: "test", name: "test", org_id: "org"}`

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: CRUD Operations

### Overview
Implement all CRUD functions: `list/1`, `stream/1`, `create/1`, `get/2`, `update/2`, `delete/2`. Each function creates a client, makes the API call, and converts the response to struct(s).

### Changes Required:

#### 1. Add Helper Functions
**File**: `lib/braintrust/project.ex`
**Changes**: Add private helper to convert API maps to structs

```elixir
  # Private helper to convert API response map to struct
  defp to_struct(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      name: map["name"],
      org_id: map["org_id"],
      user_id: map["user_id"],
      created_at: parse_datetime(map["created_at"]),
      deleted_at: parse_datetime(map["deleted_at"]),
      settings: map["settings"]
    }
  end

  defp parse_datetime(nil), do: nil
  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      {:error, _} -> nil
    end
  end
```

#### 2. Implement list/1
**File**: `lib/braintrust/project.ex`
**Changes**: Add list function with pagination support

```elixir
  @doc """
  Lists all projects.

  Returns all projects as a list. For large result sets, consider using
  `stream/1` for memory-efficient lazy loading.

  ## Options

    * `:limit` - Number of results per page (default: 100)
    * `:starting_after` - Cursor for pagination
    * `:project_name` - Filter by project name
    * `:org_name` - Filter by organization name
    * `:ids` - Filter by specific project IDs (list of strings)
    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, projects} = Braintrust.Project.list(limit: 10)
      iex> is_list(projects)
      true

  """
  @spec list(keyword()) :: {:ok, [t()]} | {:error, Error.t()}
  def list(opts \\ []) do
    {client_opts, query_opts} = split_opts(opts)
    client = Client.new(client_opts)
    params = build_list_params(query_opts)

    case Client.get_all(client, @api_path, params: params) do
      {:ok, items} -> {:ok, Enum.map(items, &to_struct/1)}
      {:error, _} = error -> error
    end
  end

  defp split_opts(opts) do
    Keyword.split(opts, [:api_key, :base_url, :timeout, :max_retries])
  end

  defp build_list_params(opts) do
    []
    |> maybe_add(:limit, opts[:limit])
    |> maybe_add(:starting_after, opts[:starting_after])
    |> maybe_add(:ending_before, opts[:ending_before])
    |> maybe_add(:project_name, opts[:project_name])
    |> maybe_add(:org_name, opts[:org_name])
    |> maybe_add(:ids, opts[:ids])
  end

  defp maybe_add(params, _key, nil), do: params
  defp maybe_add(params, key, value), do: Keyword.put(params, key, value)
```

#### 3. Implement stream/1
**File**: `lib/braintrust/project.ex`
**Changes**: Add stream function for lazy pagination

```elixir
  @doc """
  Returns a Stream that lazily paginates through all projects.

  This is memory-efficient for large result sets as it only fetches
  pages as items are consumed.

  ## Options

  Same as `list/1`.

  ## Examples

      # Take first 50 projects
      Braintrust.Project.stream(limit: 25)
      |> Stream.take(50)
      |> Enum.to_list()

      # Process all projects without loading all into memory
      Braintrust.Project.stream()
      |> Stream.each(&process_project/1)
      |> Stream.run()

  """
  @spec stream(keyword()) :: Enumerable.t()
  def stream(opts \\ []) do
    {client_opts, query_opts} = split_opts(opts)
    client = Client.new(client_opts)
    params = build_list_params(query_opts)

    client
    |> Client.get_stream(@api_path, params: params)
    |> Stream.map(&to_struct/1)
  end
```

#### 4. Implement get/2
**File**: `lib/braintrust/project.ex`
**Changes**: Add get function

```elixir
  @doc """
  Gets a project by ID.

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, project} = Braintrust.Project.get("proj_123")
      iex> project.name
      "my-project"

  """
  @spec get(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def get(project_id, opts \\ []) do
    client = Client.new(opts)

    case Client.get(client, "#{@api_path}/#{project_id}") do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, _} = error -> error
    end
  end
```

#### 5. Implement create/1
**File**: `lib/braintrust/project.ex`
**Changes**: Add create function

```elixir
  @doc """
  Creates a new project.

  If a project with the same name already exists, returns the existing
  project unmodified (idempotent behavior).

  ## Parameters

    * `:name` - Project name (required)
    * `:settings` - Project settings map (optional)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, project} = Braintrust.Project.create(%{name: "my-project"})
      iex> project.name
      "my-project"

      # With settings
      iex> {:ok, project} = Braintrust.Project.create(%{
      ...>   name: "my-project",
      ...>   settings: %{comparison_key: "input"}
      ...> })

  """
  @spec create(map(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def create(params, opts \\ []) do
    client = Client.new(opts)

    case Client.post(client, @api_path, params) do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, _} = error -> error
    end
  end
```

#### 6. Implement update/2
**File**: `lib/braintrust/project.ex`
**Changes**: Add update function

```elixir
  @doc """
  Updates a project.

  Uses PATCH semantics - only provided fields are updated. Object fields
  like `settings` support deep merge.

  ## Parameters

    * `:name` - New project name
    * `:settings` - Settings to merge (deep merge for nested objects)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, project} = Braintrust.Project.update("proj_123", %{name: "new-name"})
      iex> project.name
      "new-name"

      # Update settings (deep merge)
      iex> {:ok, project} = Braintrust.Project.update("proj_123", %{
      ...>   settings: %{comparison_key: "output"}
      ...> })

  """
  @spec update(String.t(), map(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def update(project_id, params, opts \\ []) do
    client = Client.new(opts)

    case Client.patch(client, "#{@api_path}/#{project_id}", params) do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, _} = error -> error
    end
  end
```

#### 7. Implement delete/2
**File**: `lib/braintrust/project.ex`
**Changes**: Add delete function

```elixir
  @doc """
  Deletes a project.

  This is a soft delete - the project's `deleted_at` field will be set.

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, project} = Braintrust.Project.delete("proj_123")
      iex> project.deleted_at != nil
      true

  """
  @spec delete(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def delete(project_id, opts \\ []) do
    client = Client.new(opts)

    case Client.delete(client, "#{@api_path}/#{project_id}") do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, _} = error -> error
    end
  end
```

### Success Criteria:

#### Automated Verification:
- [x] Module compiles: `mix compile`
- [x] Code formatting passes: `mix format --check-formatted`
- [x] Credo passes: `mix credo --strict`
- [x] Dialyzer passes: `mix dialyzer`

#### Manual Verification:
- [ ] Functions are callable in IEx (will fail without API key, but should compile)
- [ ] Documentation renders correctly: `mix docs && open doc/Braintrust.Project.html`

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 3: Tests

### Overview
Add comprehensive tests for the Project module using Mimic to mock Req calls, following patterns from existing tests.

### Changes Required:

#### 1. Create Project Test File
**File**: `test/braintrust/project_test.exs` (new)
**Changes**: Add test module with setup and test cases

```elixir
defmodule Braintrust.ProjectTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Braintrust.{Client, Config, Error, Project}

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
    test "returns list of project structs" do
      response = %{
        "objects" => [
          %{"id" => "proj_1", "name" => "project-1", "org_id" => "org_1"},
          %{"id" => "proj_2", "name" => "project-2", "org_id" => "org_1"}
        ]
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, projects} = Project.list()
      assert length(projects) == 2
      assert [%Project{id: "proj_1"}, %Project{id: "proj_2"}] = projects
    end

    test "passes query parameters" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:limit] == 10
        assert opts[:params][:project_name] == "test"
        {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
      end)

      assert {:ok, []} = Project.list(limit: 10, project_name: "test")
    end

    test "returns error on failure" do
      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Project.list()
    end
  end

  describe "stream/1" do
    test "returns a stream of project structs" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      stub(Req, :request, fn _client, _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            {:ok, %Req.Response{
              status: 200,
              body: %{"objects" => [%{"id" => "proj_1", "name" => "p1", "org_id" => "org"}]},
              headers: []
            }}
          _ ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      projects = Project.stream() |> Enum.to_list()
      assert [%Project{id: "proj_1"}] = projects

      Agent.stop(agent)
    end
  end

  describe "get/2" do
    test "returns project struct on success" do
      response = %{
        "id" => "proj_123",
        "name" => "my-project",
        "org_id" => "org_1",
        "created_at" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/project/proj_123"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.get("proj_123")
      assert %Project{id: "proj_123", name: "my-project"} = project
      assert %DateTime{} = project.created_at
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{
          status: 404,
          body: %{"error" => %{"message" => "Project not found"}},
          headers: []
        }}
      end)

      assert {:error, %Error{type: :not_found}} = Project.get("invalid")
    end
  end

  describe "create/2" do
    test "creates and returns project struct" do
      response = %{
        "id" => "proj_new",
        "name" => "new-project",
        "org_id" => "org_1"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:json] == %{name: "new-project"}
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.create(%{name: "new-project"})
      assert %Project{id: "proj_new", name: "new-project"} = project
    end

    test "returns existing project if name exists (idempotent)" do
      response = %{
        "id" => "proj_existing",
        "name" => "existing-project",
        "org_id" => "org_1"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.create(%{name: "existing-project"})
      assert project.id == "proj_existing"
    end

    test "returns error on validation failure" do
      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{
          status: 400,
          body: %{"error" => %{"message" => "Name is required"}},
          headers: []
        }}
      end)

      assert {:error, %Error{type: :bad_request, message: "Name is required"}} =
               Project.create(%{})
    end
  end

  describe "update/3" do
    test "updates and returns project struct" do
      response = %{
        "id" => "proj_123",
        "name" => "updated-name",
        "org_id" => "org_1"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json] == %{name: "updated-name"}
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.update("proj_123", %{name: "updated-name"})
      assert project.name == "updated-name"
    end
  end

  describe "delete/2" do
    test "deletes and returns project with deleted_at set" do
      response = %{
        "id" => "proj_123",
        "name" => "deleted-project",
        "org_id" => "org_1",
        "deleted_at" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.delete("proj_123")
      assert %DateTime{} = project.deleted_at
    end

    test "returns error on permission denied" do
      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{
          status: 403,
          body: %{"error" => %{"message" => "Permission denied"}},
          headers: []
        }}
      end)

      assert {:error, %Error{type: :permission_denied}} = Project.delete("proj_123")
    end
  end

  describe "to_struct/1 (via public functions)" do
    test "parses datetime fields correctly" do
      response = %{
        "id" => "proj_1",
        "name" => "test",
        "org_id" => "org_1",
        "created_at" => "2024-01-15T14:15:22Z",
        "deleted_at" => nil
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.get("proj_1")
      assert %DateTime{year: 2024, month: 1, day: 15} = project.created_at
      assert project.deleted_at == nil
    end

    test "handles missing optional fields" do
      response = %{
        "id" => "proj_1",
        "name" => "test",
        "org_id" => "org_1"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, project} = Project.get("proj_1")
      assert project.user_id == nil
      assert project.created_at == nil
      assert project.settings == nil
    end
  end
end
```

### Success Criteria:

#### Automated Verification:
- [x] All tests pass: `mix test test/braintrust/project_test.exs`
- [x] Full test suite passes: `mix test`
- [x] Quality checks pass: `mix quality --quick`

#### Manual Verification:
- [ ] Test output is clean with no warnings
- [ ] Code coverage includes new module

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 4: Documentation & Final Cleanup

### Overview
Update main module documentation to reference the new Project module, and ensure all doctests work.

### Changes Required:

#### 1. Update Main Module
**File**: `lib/braintrust.ex`
**Changes**: Update the "coming soon" reference

```elixir
# Change line 36 from:
  - `Braintrust.Project` - Manage projects (coming soon)
# To:
  - `Braintrust.Project` - Manage projects
```

### Success Criteria:

#### Automated Verification:
- [x] All quality checks pass: `mix quality --quick`
- [x] Documentation generates: `mix docs`

#### Manual Verification:
- [ ] Documentation looks correct in generated docs
- [ ] All acceptance criteria from GitHub issue #11 are met

---

## Testing Strategy

### Unit Tests:
- All CRUD operations with success cases
- Error handling for each HTTP status code
- DateTime parsing edge cases
- Query parameter passing
- Stream pagination behavior

### Doctests:
- Basic usage examples in `@doc` blocks
- Will be skipped in actual runs since they require API calls

### Manual Testing Steps:
1. Create a test project via IEx with real API key
2. Verify list returns the created project
3. Update the project and verify changes
4. Delete the project and verify soft delete
5. Verify error handling with invalid project ID

## Performance Considerations

- `stream/1` is memory-efficient for large result sets
- `list/1` eagerly loads all results - suitable for small-medium datasets
- Each CRUD operation creates a new HTTP client instance (acceptable for this use case)

## Migration Notes

N/A - This is a new module with no existing functionality to migrate.

## References

- Source document: GitHub Issue #11
- Related research: `thoughts/shared/research/braintrust_hex_package.md` (lines 158-198)
- API Documentation: https://www.braintrust.dev/docs/reference/api/Projects
- Similar implementation patterns: `lib/braintrust/client.ex`, `lib/braintrust/error.ex`
