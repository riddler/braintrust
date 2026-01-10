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

  alias Braintrust.{Client, Error, Span}

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

  # =============================================================================
  # Dataset-Specific Operations
  # =============================================================================

  @doc """
  Inserts dataset records.

  Records represent test cases with input data and optional expected outputs.
  Every insert is versioned via `_xact_id` for reproducibility.

  ## Parameters

    * `records` - List of record maps or `%Braintrust.Span{}` structs, each containing:
      * `:input` - Input data to recreate the example (required)
      * `:expected` - Expected output for scoring (optional)
      * `:metadata` - Custom metadata map (optional)
      * `:id` - Unique record ID (optional, auto-generated if not provided)

  ## Options

    * `:api_key` - Override API key for this request
    * `:base_url` - Override base URL for this request

  ## Examples

      # With raw maps
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

      # With Span structs
      iex> spans = [%Braintrust.Span{input: %{q: "test"}, expected: "answer"}]
      iex> {:ok, result} = Braintrust.Dataset.insert("ds_123", spans)

  """
  @spec insert(String.t(), [map() | Span.t()], keyword()) :: {:ok, map()} | {:error, Error.t()}
  def insert(dataset_id, records, opts \\ []) when is_list(records) do
    client = Client.new(opts)
    normalized_records = Enum.map(records, &normalize_record/1)
    body = %{events: normalized_records}

    Client.post(client, "#{@api_path}/#{dataset_id}/insert", body)
  end

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

  # Private Functions

  defp normalize_record(%Span{} = span), do: Span.to_map(span)
  defp normalize_record(record) when is_map(record), do: record

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
end
