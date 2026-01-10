# Prompts Resource Module Implementation Plan

## Overview

Implement the `Braintrust.Prompt` resource module for version-controlled prompt management. This follows the established patterns from `Braintrust.Project`, `Braintrust.Experiment`, and `Braintrust.Dataset`.

## Current State Analysis

The codebase has a well-established pattern for resource modules:

- **Struct + functions colocated** in a single module (e.g., `lib/braintrust/project.ex`)
- **CRUD operations** via `Client.get/post/patch/delete`
- **Pagination** via `Braintrust.Resource.list_all/3` and `stream_all/3`
- **Return types**: `{:ok, result}` or `{:error, %Braintrust.Error{}}`
- **Tests** use Mimic to stub HTTP requests

### Key Discoveries:
- `Braintrust.Resource` helper module handles pagination boilerplate (`lib/braintrust/resource.ex:1-75`)
- All resources follow identical patterns for `list/1`, `stream/1`, `get/2`, `create/2`, `update/3`, `delete/2`
- Test helpers in `test/support/test_helpers.ex` provide pagination stubs
- DateTime parsing helper is duplicated in each module - uses `DateTime.from_iso8601/1`
- **Field mapping convention**: API response uses `"created"` but struct uses `:created_at` for Elixir naming consistency (see `lib/braintrust/project.ex:249`)

## Desired End State

A complete `Braintrust.Prompt` module that:
1. Defines the `%Braintrust.Prompt{}` struct with all fields from the API
2. Implements all CRUD operations matching existing patterns
3. Supports version/xact_id query parameters for `get/2`
4. Includes comprehensive doctests and unit tests
5. Passes all quality checks (`mix quality`)

### Verification:
```bash
# Run tests
mix test test/braintrust/prompt_test.exs

# Run quality checks
mix quality
```

## What We're NOT Doing

- **Client-side caching**: The issue mentions "client-side caching with disk persistence" as a future enhancement
- **Template variable rendering**: We're storing `{{variable}}` syntax but not rendering it
- **Slug-based retrieval**: Not implementing separate slug lookup - user can use `get/2` with version params
- **Integration with `/v1/function` endpoint**: Prompts are also accessible via functions, but we're implementing the dedicated `/v1/prompt` endpoint

## Implementation Approach

Follow the exact patterns established in `Braintrust.Experiment` and `Braintrust.Dataset`:
1. Create the module with struct definition
2. Implement CRUD operations delegating to `Braintrust.Resource` for list/stream
3. Add version support to `get/2` via query parameters
4. Write comprehensive tests with mocked HTTP responses

## Phase 1: Create Braintrust.Prompt Module

### Overview
Create the `lib/braintrust/prompt.ex` module with struct, CRUD operations, and doctests.

### Changes Required:

#### 1. Create `lib/braintrust/prompt.ex`

**File**: `lib/braintrust/prompt.ex`
**Changes**: New file with complete implementation

```elixir
defmodule Braintrust.Prompt do
  @moduledoc """
  Manage Braintrust prompts.

  Prompts are version-controlled, evaluated artifacts that integrate with
  Braintrust's evaluation infrastructure and staged deployment workflows.

  ## Examples

      # List all prompts
      {:ok, prompts} = Braintrust.Prompt.list()

      # List prompts for a specific project
      {:ok, prompts} = Braintrust.Prompt.list(project_id: "proj_123")

      # Create a prompt
      {:ok, prompt} = Braintrust.Prompt.create(%{
        project_id: "proj_123",
        name: "customer-support",
        slug: "customer-support-v1",
        model: "gpt-4",
        messages: [
          %{role: "system", content: "You are a helpful customer support agent."},
          %{role: "user", content: "{{user_input}}"}
        ]
      })

      # Get a prompt by ID
      {:ok, prompt} = Braintrust.Prompt.get("prompt_123")

      # Get a specific version
      {:ok, prompt} = Braintrust.Prompt.get("prompt_123", version: "v2")

      # Update a prompt (creates new version)
      {:ok, prompt} = Braintrust.Prompt.update("prompt_123", %{
        messages: [...]
      })

      # Delete a prompt
      {:ok, prompt} = Braintrust.Prompt.delete("prompt_123")

  ## Pagination

  The `list/1` function supports cursor-based pagination:

      # Get all prompts as a list
      {:ok, prompts} = Braintrust.Prompt.list()

      # Stream through prompts lazily
      Braintrust.Prompt.stream()
      |> Stream.take(100)
      |> Enum.to_list()

  ## Versioning

  Prompts are versioned via `_xact_id` (transaction ID). Retrieve specific
  versions using the `:version` or `:xact_id` options in `get/2`.

  ## Template Variables

  Message content supports `{{variable}}` syntax for template variables.
  These are replaced at runtime when the prompt is used.

  """

  alias Braintrust.{Client, Error}

  @type message :: %{
          required(:role) => String.t(),
          required(:content) => String.t()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          org_id: String.t() | nil,
          project_id: String.t() | nil,
          name: String.t(),
          slug: String.t() | nil,
          description: String.t() | nil,
          model: String.t() | nil,
          messages: [message()] | nil,
          tools: [map()] | nil,
          tool_choice: String.t() | map() | nil,
          function_type: String.t() | nil,
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
    :model,
    :messages,
    :tools,
    :tool_choice,
    :function_type,
    :user_id,
    :metadata,
    :created_at,
    :deleted_at
  ]

  @api_path "/v1/prompt"

  @doc """
  Lists all prompts.

  Returns all prompts as a list. For large result sets, consider using
  `stream/1` for memory-efficient lazy loading.

  ## Options

    * `:limit` - Number of results per page (default: 100)
    * `:starting_after` - Cursor for pagination
    * `:project_id` - Filter by project ID
    * `:prompt_name` - Filter by prompt name
    * `:slug` - Filter by prompt slug
    * `:org_name` - Filter by organization name
    * `:ids` - Filter by specific prompt IDs (list of strings)
    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, prompts} = Braintrust.Prompt.list(limit: 10)
      iex> is_list(prompts)
      true

  """
  @spec list(keyword()) :: {:ok, [t()]} | {:error, Error.t()}
  def list(opts \\ []) do
    Braintrust.Resource.list_all(@api_path, opts, &to_struct/1)
  end

  @doc """
  Returns a Stream that lazily paginates through all prompts.

  This is memory-efficient for large result sets as it only fetches
  pages as items are consumed.

  ## Options

  Same as `list/1`.

  ## Examples

      # Take first 50 prompts
      Braintrust.Prompt.stream(limit: 25)
      |> Stream.take(50)
      |> Enum.to_list()

      # Process all prompts without loading all into memory
      Braintrust.Prompt.stream()
      |> Stream.each(&process_prompt/1)
      |> Stream.run()

  """
  @spec stream(keyword()) :: Enumerable.t()
  def stream(opts \\ []) do
    Braintrust.Resource.stream_all(@api_path, opts, &to_struct/1)
  end

  @doc """
  Gets a prompt by ID.

  ## Options

    * `:version` - Specific version identifier to retrieve
    * `:xact_id` - Transaction ID for exact version
    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, prompt} = Braintrust.Prompt.get("prompt_123")
      iex> prompt.name
      "customer-support"

      # Get a specific version
      iex> {:ok, prompt} = Braintrust.Prompt.get("prompt_123", version: "v2")

  """
  @spec get(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def get(prompt_id, opts \\ []) do
    {client_opts, query_opts} = Braintrust.Resource.split_opts(opts)
    client = Client.new(client_opts)

    params =
      []
      |> Braintrust.Resource.maybe_add(:version, query_opts[:version])
      |> Braintrust.Resource.maybe_add(:xact_id, query_opts[:xact_id])

    request_opts = if params == [], do: [], else: [params: params]

    case Client.get(client, "#{@api_path}/#{prompt_id}", request_opts) do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Creates a new prompt.

  If a prompt with the same name/slug already exists within the project,
  returns the existing prompt unmodified (idempotent behavior).

  ## Parameters

    * `:project_id` - Project ID (required)
    * `:name` - Prompt name (required)
    * `:slug` - Unique identifier for stable references (optional)
    * `:description` - Prompt description (optional)
    * `:model` - Model to use (e.g., "gpt-4") (optional)
    * `:messages` - List of message maps with :role and :content (optional)
    * `:tools` - Tool/function definitions for function calling (optional)
    * `:tool_choice` - Tool selection preference (optional)
    * `:metadata` - Custom metadata map (optional)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, prompt} = Braintrust.Prompt.create(%{
      ...>   project_id: "proj_123",
      ...>   name: "my-prompt",
      ...>   slug: "my-prompt-v1",
      ...>   model: "gpt-4",
      ...>   messages: [
      ...>     %{role: "system", content: "You are helpful."},
      ...>     %{role: "user", content: "{{query}}"}
      ...>   ]
      ...> })
      iex> prompt.name
      "my-prompt"

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
  Updates a prompt.

  Uses PATCH semantics - only provided fields are updated. Updating a prompt
  creates a new version; previous versions remain accessible via version/xact_id.

  ## Parameters

    * `:name` - New prompt name
    * `:slug` - New slug identifier
    * `:description` - New description
    * `:model` - New model
    * `:messages` - Updated message list
    * `:tools` - Updated tool definitions
    * `:tool_choice` - Updated tool choice
    * `:metadata` - Metadata to merge (deep merge for nested objects)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, prompt} = Braintrust.Prompt.update("prompt_123", %{
      ...>   messages: [
      ...>     %{role: "system", content: "Updated system prompt."},
      ...>     %{role: "user", content: "{{query}}"}
      ...>   ]
      ...> })
      iex> length(prompt.messages)
      2

  """
  @spec update(String.t(), map(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def update(prompt_id, params, opts \\ []) do
    client = Client.new(opts)

    case Client.patch(client, "#{@api_path}/#{prompt_id}", params) do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Deletes a prompt.

  This is a soft delete - the prompt's `deleted_at` field will be set.

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      iex> {:ok, prompt} = Braintrust.Prompt.delete("prompt_123")
      iex> prompt.deleted_at != nil
      true

  """
  @spec delete(String.t(), keyword()) :: {:ok, t()} | {:error, Error.t()}
  def delete(prompt_id, opts \\ []) do
    client = Client.new(opts)

    case Client.delete(client, "#{@api_path}/#{prompt_id}") do
      {:ok, data} -> {:ok, to_struct(data)}
      {:error, error} -> {:error, error}
    end
  end

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
      model: map["model"],
      messages: map["messages"],
      tools: map["tools"],
      tool_choice: map["tool_choice"],
      function_type: map["function_type"],
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

### Success Criteria:

#### Automated Verification:
- [x] Module compiles: `mix compile`
- [x] Code formatting passes: `mix format --check-formatted`

---

## Phase 2: Update Resource Filter Parameters

### Overview
Add `prompt_name` and `slug` to the `Braintrust.Resource` filter parameters.

### Changes Required:

#### 1. Update `lib/braintrust/resource.ex`
**File**: `lib/braintrust/resource.ex`
**Changes**: Add prompt-specific filter parameters

```elixir
# In build_filter_params/2, add these lines after existing filters:
|> maybe_add(:prompt_name, filter_params[:prompt_name])
|> maybe_add(:slug, filter_params[:slug])
# And in the second block:
|> maybe_add(:prompt_name, all_opts[:prompt_name])
|> maybe_add(:slug, all_opts[:slug])
```

### Success Criteria:

#### Automated Verification:
- [x] Module compiles: `mix compile`
- [x] Existing tests pass: `mix test`

---

## Phase 3: Write Unit Tests

### Overview
Create comprehensive tests for `Braintrust.Prompt` following the patterns in `experiment_test.exs`.

### Changes Required:

#### 1. Create `test/braintrust/prompt_test.exs`

**File**: `test/braintrust/prompt_test.exs`
**Changes**: New test file

```elixir
defmodule Braintrust.PromptTest do
  use ExUnit.Case, async: true
  use Mimic

  import Braintrust.TestHelpers

  alias Braintrust.{Config, Error, Prompt}

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
    test "returns list of prompt structs" do
      response = %{
        "objects" => [
          %{
            "id" => "prompt_1",
            "name" => "prompt-1",
            "project_id" => "proj_1",
            "slug" => "prompt-1-v1"
          },
          %{
            "id" => "prompt_2",
            "name" => "prompt-2",
            "project_id" => "proj_1",
            "slug" => "prompt-2-v1"
          }
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      assert {:ok, prompts} = Prompt.list()
      assert length(prompts) == 2
      assert [%Prompt{id: "prompt_1"}, %Prompt{id: "prompt_2"}] = prompts

      Agent.stop(agent)
    end

    test "passes filter parameters" do
      {:ok, agent} = start_pagination_agent()

      stub(Req, :request, fn _client, opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            assert opts[:params][:project_id] == "proj_123"
            assert opts[:params][:prompt_name] == "test"
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}

          _page ->
            {:ok, %Req.Response{status: 200, body: %{"objects" => []}, headers: []}}
        end
      end)

      assert {:ok, []} = Prompt.list(project_id: "proj_123", prompt_name: "test")

      Agent.stop(agent)
    end

    test "returns error on failure" do
      stub(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
      end)

      assert {:error, %Error{type: :server_error}} = Prompt.list()
    end
  end

  describe "stream/1" do
    test "returns a stream of prompt structs" do
      response = %{
        "objects" => [
          %{"id" => "prompt_1", "name" => "p1", "project_id" => "proj_1", "slug" => "p1-v1"}
        ]
      }

      {:ok, agent} = start_pagination_agent()
      stub(Req, :request, paginated_stub(agent, response))

      prompts = Prompt.stream() |> Enum.to_list()
      assert [%Prompt{id: "prompt_1"}] = prompts

      Agent.stop(agent)
    end
  end

  describe "get/2" do
    test "returns prompt struct on success" do
      response = %{
        "id" => "prompt_123",
        "name" => "my-prompt",
        "project_id" => "proj_1",
        "slug" => "my-prompt-v1",
        "model" => "gpt-4",
        "messages" => [
          %{"role" => "system", "content" => "You are helpful."},
          %{"role" => "user", "content" => "{{query}}"}
        ],
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:url] == "/v1/prompt/prompt_123"
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.get("prompt_123")
      assert %Prompt{id: "prompt_123", name: "my-prompt"} = prompt
      assert prompt.model == "gpt-4"
      assert length(prompt.messages) == 2
      assert %DateTime{} = prompt.created_at
    end

    test "supports version parameter" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:version] == "v2"
        {:ok, %Req.Response{status: 200, body: %{"id" => "prompt_123", "name" => "test"}, headers: []}}
      end)

      assert {:ok, _prompt} = Prompt.get("prompt_123", version: "v2")
    end

    test "supports xact_id parameter" do
      expect(Req, :request, fn _client, opts ->
        assert opts[:params][:xact_id] == "xact_abc123"
        {:ok, %Req.Response{status: 200, body: %{"id" => "prompt_123", "name" => "test"}, headers: []}}
      end)

      assert {:ok, _prompt} = Prompt.get("prompt_123", xact_id: "xact_abc123")
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Prompt not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Prompt.get("invalid")
    end
  end

  describe "create/2" do
    test "creates and returns prompt struct" do
      response = %{
        "id" => "prompt_new",
        "project_id" => "proj_123",
        "name" => "new-prompt",
        "slug" => "new-prompt-v1",
        "model" => "gpt-4"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:json][:name] == "new-prompt"
        assert opts[:json][:project_id] == "proj_123"
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.create(%{
        project_id: "proj_123",
        name: "new-prompt",
        slug: "new-prompt-v1",
        model: "gpt-4"
      })
      assert %Prompt{id: "prompt_new", name: "new-prompt"} = prompt
    end

    test "creates prompt with messages" do
      messages = [
        %{role: "system", content: "You are helpful."},
        %{role: "user", content: "{{input}}"}
      ]

      response = %{
        "id" => "prompt_new",
        "project_id" => "proj_123",
        "name" => "chat-prompt",
        "messages" => messages
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:json][:messages] == messages
        {:ok, %Req.Response{status: 201, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.create(%{
        project_id: "proj_123",
        name: "chat-prompt",
        messages: messages
      })
      assert length(prompt.messages) == 2
    end

    test "returns existing prompt if name exists (idempotent)" do
      response = %{
        "id" => "prompt_existing",
        "project_id" => "proj_123",
        "name" => "existing-prompt"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.create(%{
        project_id: "proj_123",
        name: "existing-prompt"
      })
      assert prompt.id == "prompt_existing"
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
               Prompt.create(%{name: "test"})
    end
  end

  describe "update/3" do
    test "updates and returns prompt struct" do
      response = %{
        "id" => "prompt_123",
        "project_id" => "proj_1",
        "name" => "prompt",
        "model" => "gpt-4-turbo"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json] == %{model: "gpt-4-turbo"}
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.update("prompt_123", %{model: "gpt-4-turbo"})
      assert prompt.model == "gpt-4-turbo"
    end

    test "updates messages" do
      new_messages = [
        %{role: "system", content: "Updated system prompt."},
        %{role: "user", content: "{{query}}"}
      ]

      response = %{
        "id" => "prompt_123",
        "project_id" => "proj_1",
        "name" => "prompt",
        "messages" => new_messages
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json][:messages] == new_messages
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.update("prompt_123", %{messages: new_messages})
      assert length(prompt.messages) == 2
    end

    test "returns error on not found" do
      expect(Req, :request, fn _client, _opts ->
        {:ok,
         %Req.Response{
           status: 404,
           body: %{"error" => %{"message" => "Prompt not found"}},
           headers: []
         }}
      end)

      assert {:error, %Error{type: :not_found}} = Prompt.update("invalid", %{name: "new-name"})
    end
  end

  describe "delete/2" do
    test "deletes and returns prompt with deleted_at set" do
      response = %{
        "id" => "prompt_123",
        "project_id" => "proj_1",
        "name" => "deleted-prompt",
        "deleted_at" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.delete("prompt_123")
      assert %DateTime{} = prompt.deleted_at
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

      assert {:error, %Error{type: :permission_denied}} = Prompt.delete("prompt_123")
    end
  end

  describe "to_struct/1 (via public functions)" do
    test "parses all fields correctly" do
      response = %{
        "id" => "prompt_1",
        "org_id" => "org_1",
        "project_id" => "proj_1",
        "name" => "test-prompt",
        "slug" => "test-prompt-v1",
        "description" => "Test description",
        "model" => "gpt-4",
        "messages" => [%{"role" => "system", "content" => "Hello"}],
        "tools" => [%{"type" => "function", "function" => %{}}],
        "tool_choice" => "auto",
        "function_type" => "prompt",
        "user_id" => "user_1",
        "metadata" => %{"key" => "value"},
        "created" => "2024-01-15T14:15:22Z",
        "deleted_at" => nil
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.get("prompt_1")
      assert prompt.id == "prompt_1"
      assert prompt.org_id == "org_1"
      assert prompt.project_id == "proj_1"
      assert prompt.name == "test-prompt"
      assert prompt.slug == "test-prompt-v1"
      assert prompt.description == "Test description"
      assert prompt.model == "gpt-4"
      assert length(prompt.messages) == 1
      assert length(prompt.tools) == 1
      assert prompt.tool_choice == "auto"
      assert prompt.function_type == "prompt"
      assert prompt.user_id == "user_1"
      assert prompt.metadata == %{"key" => "value"}
      assert %DateTime{year: 2024, month: 1, day: 15} = prompt.created_at
      assert prompt.deleted_at == nil
    end

    test "handles missing optional fields" do
      response = %{
        "id" => "prompt_1",
        "name" => "test"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.get("prompt_1")
      assert prompt.project_id == nil
      assert prompt.slug == nil
      assert prompt.model == nil
      assert prompt.messages == nil
      assert prompt.tools == nil
      assert prompt.created_at == nil
    end

    test "handles invalid datetime strings" do
      response = %{
        "id" => "prompt_1",
        "name" => "test",
        "created" => "invalid-date"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.get("prompt_1")
      assert prompt.created_at == nil
    end

    test "maps 'created' API field to 'created_at' struct field" do
      response = %{
        "id" => "prompt_1",
        "name" => "test",
        "created" => "2024-01-15T14:15:22Z"
      }

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 200, body: response, headers: []}}
      end)

      assert {:ok, prompt} = Prompt.get("prompt_1")
      # Verify that the 'created' field from API is mapped to created_at in struct
      assert %DateTime{} = prompt.created_at
      assert prompt.created_at.year == 2024
    end
  end
end
```

### Success Criteria:

#### Automated Verification:
- [x] All tests pass: `mix test test/braintrust/prompt_test.exs`
- [x] All quality checks pass: `mix quality`

#### Manual Verification:
- [ ] Documentation is clear and examples make sense
- [ ] API matches the Braintrust documentation

**Implementation Note**: After completing this phase and all automated verification passes, the implementation is complete. Verify with `mix quality` that all checks pass.

---

## Testing Strategy

### Unit Tests:
- Test all CRUD operations with mocked HTTP responses
- Test pagination (list and stream)
- Test version/xact_id parameters in get/2
- Test error handling for all operations
- Test struct field parsing including datetime conversion

### Integration Tests (Manual):
- Create a prompt and verify it appears in list
- Update a prompt and verify new version is created
- Get a prompt by version/xact_id
- Delete a prompt and verify deleted_at is set

### Manual Testing Steps:
1. Start IEx with API key: `BRAINTRUST_API_KEY=sk-xxx iex -S mix`
2. Create a prompt: `Braintrust.Prompt.create(%{project_id: "...", name: "test"})`
3. List prompts: `Braintrust.Prompt.list(project_id: "...")`
4. Get the prompt: `Braintrust.Prompt.get("prompt_id")`
5. Update the prompt: `Braintrust.Prompt.update("prompt_id", %{model: "gpt-4"})`
6. Delete the prompt: `Braintrust.Prompt.delete("prompt_id")`

## References

- GitHub issue: `#16`
- Research: `thoughts/shared/research/braintrust_hex_package.md`
- Similar implementations:
  - `lib/braintrust/experiment.ex`
  - `lib/braintrust/dataset.ex`
  - `lib/braintrust/project.ex`
- [Prompts API](https://www.braintrust.dev/docs/reference/api/Prompts)
