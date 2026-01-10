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
    Braintrust.Resource.list_all(@api_path, opts, &to_struct/1)
  end

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
    Braintrust.Resource.stream_all(@api_path, opts, &to_struct/1)
  end

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
      {:error, error} -> {:error, error}
    end
  end

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
      {:error, error} -> {:error, error}
    end
  end

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
      {:error, error} -> {:error, error}
    end
  end

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
      {:error, error} -> {:error, error}
    end
  end

  # Private Functions

  # Private helper to convert API response map to struct
  defp to_struct(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      name: map["name"],
      org_id: map["org_id"],
      user_id: map["user_id"],
      created_at: parse_datetime(map["created"]),
      deleted_at: parse_datetime(map["deleted_at"]),
      settings: map["settings"]
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
