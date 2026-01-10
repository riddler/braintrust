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
