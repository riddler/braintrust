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

  alias Braintrust.{Client, Error, Span}

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
    Braintrust.Resource.list_all(@api_path, opts, &to_struct/1)
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
    Braintrust.Resource.stream_all(@api_path, opts, &to_struct/1)
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

  # =============================================================================
  # Experiment-Specific Operations
  # =============================================================================

  @doc """
  Inserts experiment events.

  Events are the core data structure for experiment results. Each event
  represents a single evaluation with input, output, and optional scores.

  ## Parameters

    * `events` - List of event maps or `%Braintrust.Span{}` structs, each containing:
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

      # With raw maps
      iex> {:ok, result} = Braintrust.Experiment.insert("exp_123", [
      ...>   %{
      ...>     input: %{messages: [%{role: "user", content: "What is 2+2?"}]},
      ...>     output: "4",
      ...>     scores: %{accuracy: 1.0},
      ...>     metadata: %{model: "gpt-4"}
      ...>   }
      ...> ])

      # With Span structs
      iex> spans = [%Braintrust.Span{input: %{q: "test"}, output: "result"}]
      iex> {:ok, result} = Braintrust.Experiment.insert("exp_123", spans)

  """
  @spec insert(String.t(), [map() | Span.t()], keyword()) :: {:ok, map()} | {:error, Error.t()}
  def insert(experiment_id, events, opts \\ []) when is_list(events) do
    client = Client.new(opts)
    normalized_events = Enum.map(events, &normalize_event/1)
    body = %{events: normalized_events}

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
    {client_opts, query_opts} = Braintrust.Resource.split_opts(opts)
    client = Client.new(client_opts)

    params =
      []
      |> Braintrust.Resource.maybe_add(:summarize_scores, query_opts[:summarize_scores])
      |> Braintrust.Resource.maybe_add(
        :comparison_experiment_id,
        query_opts[:comparison_experiment_id]
      )

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

  # Private Functions

  defp normalize_event(%Span{} = span), do: Span.to_map(span)
  defp normalize_event(event) when is_map(event), do: event

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
