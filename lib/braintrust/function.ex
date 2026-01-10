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
end
