defmodule Braintrust.Pagination do
  @moduledoc """
  Cursor-based pagination for Braintrust API list endpoints.

  Provides both lazy Stream-based iteration and eager list functions
  for paginating through API results.

  ## Stream-based pagination (recommended for large datasets)

  Uses Elixir Streams for memory-efficient, lazy evaluation:

      # Define a fetch function that calls the API
      fetch_fn = fn opts ->
        Braintrust.Client.get(client, "/v1/project", params: opts)
      end

      # Stream through results
      Braintrust.Pagination.stream(fetch_fn, limit: 100)
      |> Stream.take(500)
      |> Enum.to_list()

  ## Eager list (fetches all pages)

      Braintrust.Pagination.list(fetch_fn, limit: 100)

  ## Duplicate filtering

  For fetch endpoints that may return duplicate items across pages:

      Braintrust.Pagination.stream(fetch_fn, unique_by: :id)

  """

  alias Braintrust.Error

  @type fetch_fn :: (keyword() -> {:ok, map()} | {:error, Error.t()})
  @type item :: map()

  @default_limit 100

  @doc """
  Creates a Stream that lazily paginates through API results.

  The stream fetches pages on-demand as items are consumed,
  making it memory-efficient for large result sets.

  ## Options

    * `:limit` - Number of items per page (default: #{@default_limit})
    * `:starting_after` - Cursor to start pagination from
    * `:unique_by` - Key to use for duplicate filtering (e.g., `:id`)

  ## Examples

      iex> fetch_fn = fn opts -> {:ok, %{"objects" => [%{"id" => "1"}]}} end
      iex> Braintrust.Pagination.stream(fetch_fn) |> Enum.take(1)
      [%{"id" => "1"}]

  """
  @spec stream(fetch_fn(), keyword()) :: Enumerable.t()
  def stream(fetch_fn, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    starting_after = Keyword.get(opts, :starting_after)
    unique_by = Keyword.get(opts, :unique_by)

    base_stream =
      Stream.resource(
        fn -> fetch_first_page(fetch_fn, limit, starting_after) end,
        &next_item(fetch_fn, limit, &1),
        fn _state -> :ok end
      )

    if unique_by do
      deduplicate(base_stream, unique_by)
    else
      base_stream
    end
  end

  @doc """
  Fetches all pages and returns a list of all items.

  This is a convenience function that eagerly consumes the entire
  paginated result set. For large datasets, prefer `stream/2`.

  ## Options

  Same as `stream/2`.

  ## Examples

      iex> fetch_fn = fn _opts -> {:ok, %{"objects" => [%{"id" => "1"}]}} end
      iex> Braintrust.Pagination.list(fetch_fn)
      {:ok, [%{"id" => "1"}]}

  """
  @spec list(fetch_fn(), keyword()) :: {:ok, [item()]} | {:error, Error.t()}
  def list(fetch_fn, opts \\ []) do
    items = stream(fetch_fn, opts) |> Enum.to_list()
    {:ok, items}
  catch
    {:pagination_error, error} -> {:error, error}
  end

  # Private Functions

  defp fetch_first_page(fetch_fn, limit, starting_after) do
    params = build_params(limit, starting_after)

    case fetch_fn.(params) do
      {:ok, %{"objects" => items}} when is_list(items) and items != [] ->
        cursor = get_cursor(items)
        {items, cursor}

      {:ok, %{"objects" => []}} ->
        {[], nil}

      {:ok, %{"objects" => _items}} ->
        {[], nil}

      {:ok, _response} ->
        # Response doesn't have expected format
        {[], nil}

      {:error, error} ->
        throw({:pagination_error, error})
    end
  end

  defp next_item(_fetch_fn, _limit, {[], nil}) do
    {:halt, nil}
  end

  defp next_item(fetch_fn, limit, {[], cursor}) when not is_nil(cursor) do
    params = build_params(limit, cursor)

    case fetch_fn.(params) do
      {:ok, %{"objects" => items}} when is_list(items) and items != [] ->
        new_cursor = get_cursor(items)
        [head | tail] = items
        {[head], {tail, new_cursor}}

      {:ok, _response} ->
        {:halt, nil}

      {:error, error} ->
        throw({:pagination_error, error})
    end
  end

  defp next_item(_fetch_fn, _limit, {[item | rest], cursor}) do
    {[item], {rest, cursor}}
  end

  defp build_params(limit, nil), do: [limit: limit]
  defp build_params(limit, cursor), do: [limit: limit, starting_after: cursor]

  defp get_cursor([]), do: nil

  defp get_cursor(items) do
    case List.last(items) do
      %{"id" => id} -> id
      _item -> nil
    end
  end

  defp deduplicate(stream, key) when is_atom(key) do
    key_fn = fn item -> Map.get(item, Atom.to_string(key)) end
    deduplicate_by(stream, key_fn)
  end

  defp deduplicate_by(stream, key_fn) do
    Stream.transform(stream, MapSet.new(), fn item, seen ->
      key = key_fn.(item)

      if MapSet.member?(seen, key) do
        {[], seen}
      else
        {[item], MapSet.put(seen, key)}
      end
    end)
  end
end
