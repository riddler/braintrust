# Cursor-Based Pagination with Stream Support - Implementation Plan

**Issue:** #9 - Implement cursor-based pagination with Stream support
**Date:** 2026-01-10

## Overview

Implement a `Braintrust.Pagination` module providing cursor-based pagination for the Braintrust Elixir SDK. This module will enable efficient listing of large collections across all resource modules using lazy Elixir Streams and manual page control.

## Current State Analysis

### Existing Infrastructure
- **HTTP Client** (`lib/braintrust/client.ex`): Complete with GET/POST/PATCH/DELETE, retry logic, and error handling
- **Error Handling** (`lib/braintrust/error.ex`): Fully implemented with typed errors and retryable detection
- **Configuration** (`lib/braintrust/config.ex`): Complete with multiple configuration sources

### Braintrust API Pagination Pattern
From research (`thoughts/shared/research/braintrust_hex_package.md:636-667`):
- Cursor-based (not offset-based)
- Parameters: `limit`, `starting_after`, `ending_before`
- **Constraint:** Only ONE cursor parameter at a time
- Response format: `{"objects": [...], "starting_after": "next-cursor-uuid"}`
- Fetch queries may return duplicates requiring ID-based filtering

## Desired End State

A `Braintrust.Pagination` module that:
1. Provides `stream/2` for lazy auto-pagination using `Stream.resource/3`
2. Provides `list/2` for eagerly fetching all pages
3. Supports duplicate filtering for fetch endpoints
4. Integrates seamlessly with future resource modules

### Key Usage Patterns

```elixir
# Stream-based (lazy, memory-efficient)
Braintrust.Pagination.stream(&fetch_fn/1, limit: 100)
|> Stream.take(500)
|> Enum.to_list()

# Eager list (fetches all pages)
Braintrust.Pagination.list(&fetch_fn/1, limit: 100)

# With duplicate filtering (for fetch endpoints)
Braintrust.Pagination.stream(&fetch_fn/1, unique_by: :id)
```

## What We're NOT Doing

- Resource modules (Project, Experiment, etc.) - separate issues
- Rate limiting between pages (handled by Client retry logic)
- `ending_before` cursor support (forward-only for now)
- BTQL query pagination (different pattern)

## Implementation Approach

Use `Stream.resource/3` with a tuple state `{buffer, cursor}` pattern. This is the canonical Elixir approach used by ExAws, ExTwilio, and other production libraries.

## Phase 1: Core Pagination Module

### Overview
Create the `Braintrust.Pagination` module with stream and list functions.

### Changes Required:

#### 1. Create `lib/braintrust/pagination.ex`

```elixir
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
        fn _ -> :ok end
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
    try do
      items = stream(fetch_fn, opts) |> Enum.to_list()
      {:ok, items}
    catch
      {:pagination_error, error} -> {:error, error}
    end
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

      {:ok, %{"objects" => _}} ->
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

  defp next_item(fetch_fn, limit, {[], cursor}) when cursor != nil do
    params = build_params(limit, cursor)

    case fetch_fn.(params) do
      {:ok, %{"objects" => items}} when is_list(items) and items != [] ->
        new_cursor = get_cursor(items)
        [head | tail] = items
        {[head], {tail, new_cursor}}

      {:ok, _} ->
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
      _ -> nil
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
```

### Success Criteria:

#### Automated Verification:
- [x] All checks pass: `mix quality`
- [x] Tests pass: `mix test`
- [x] Dialyzer passes with no errors

#### Manual Verification:
- [x] Module compiles without warnings
- [x] Doctests in module pass

---

## Phase 2: Comprehensive Tests

### Overview
Add comprehensive test coverage for the pagination module.

### Changes Required:

#### 1. Create `test/braintrust/pagination_test.exs`

```elixir
defmodule Braintrust.PaginationTest do
  use ExUnit.Case, async: true

  alias Braintrust.{Pagination, Error}

  describe "stream/2" do
    test "returns items from single page" do
      fetch_fn = fn _opts ->
        {:ok, %{"objects" => [%{"id" => "1"}, %{"id" => "2"}]}}
      end

      result = Pagination.stream(fetch_fn) |> Enum.to_list()
      assert result == [%{"id" => "1"}, %{"id" => "2"}]
    end

    test "paginates through multiple pages" do
      # Track which page we're fetching
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      fetch_fn = fn opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            assert opts[:limit] == 2
            assert opts[:starting_after] == nil
            {:ok, %{"objects" => [%{"id" => "a"}, %{"id" => "b"}]}}

          1 ->
            assert opts[:starting_after] == "b"
            {:ok, %{"objects" => [%{"id" => "c"}, %{"id" => "d"}]}}

          2 ->
            assert opts[:starting_after] == "d"
            {:ok, %{"objects" => []}}
        end
      end

      result = Pagination.stream(fetch_fn, limit: 2) |> Enum.to_list()
      assert result == [%{"id" => "a"}, %{"id" => "b"}, %{"id" => "c"}, %{"id" => "d"}]

      Agent.stop(agent)
    end

    test "handles empty first page" do
      fetch_fn = fn _opts -> {:ok, %{"objects" => []}} end

      result = Pagination.stream(fetch_fn) |> Enum.to_list()
      assert result == []
    end

    test "respects starting_after option" do
      fetch_fn = fn opts ->
        assert opts[:starting_after] == "cursor123"
        {:ok, %{"objects" => [%{"id" => "x"}]}}
      end

      result = Pagination.stream(fetch_fn, starting_after: "cursor123") |> Enum.to_list()
      assert result == [%{"id" => "x"}]
    end

    test "is lazy - only fetches pages as needed" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      fetch_fn = fn _opts ->
        Agent.update(agent, &(&1 + 1))
        {:ok, %{"objects" => [%{"id" => "item"}]}}
      end

      # Create stream but don't consume it
      _stream = Pagination.stream(fetch_fn)

      # No pages should be fetched yet
      assert Agent.get(agent, & &1) == 0

      Agent.stop(agent)
    end

    test "deduplicates items when unique_by is set" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      fetch_fn = fn _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 -> {:ok, %{"objects" => [%{"id" => "1"}, %{"id" => "2"}]}}
          1 -> {:ok, %{"objects" => [%{"id" => "2"}, %{"id" => "3"}]}}
          _ -> {:ok, %{"objects" => []}}
        end
      end

      result = Pagination.stream(fetch_fn, unique_by: :id) |> Enum.to_list()
      assert result == [%{"id" => "1"}, %{"id" => "2"}, %{"id" => "3"}]

      Agent.stop(agent)
    end

    test "Stream.take works correctly" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      fetch_fn = fn _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        items =
          for i <- 1..10 do
            %{"id" => "page#{page}-item#{i}"}
          end

        {:ok, %{"objects" => items}}
      end

      result = Pagination.stream(fetch_fn, limit: 10) |> Stream.take(5) |> Enum.to_list()
      assert length(result) == 5

      # Should only have fetched one page
      assert Agent.get(agent, & &1) == 1

      Agent.stop(agent)
    end
  end

  describe "list/2" do
    test "returns all items from all pages" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      fetch_fn = fn _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 -> {:ok, %{"objects" => [%{"id" => "1"}]}}
          1 -> {:ok, %{"objects" => [%{"id" => "2"}]}}
          _ -> {:ok, %{"objects" => []}}
        end
      end

      assert {:ok, items} = Pagination.list(fetch_fn)
      assert items == [%{"id" => "1"}, %{"id" => "2"}]

      Agent.stop(agent)
    end

    test "returns error when fetch fails" do
      fetch_fn = fn _opts ->
        {:error, Error.new(:server_error, "API error")}
      end

      assert {:error, %Error{type: :server_error}} = Pagination.list(fetch_fn)
    end

    test "returns error when fetch fails on subsequent page" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      fetch_fn = fn _opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 -> {:ok, %{"objects" => [%{"id" => "1"}]}}
          _ -> {:error, Error.new(:rate_limit, "Rate limited")}
        end
      end

      assert {:error, %Error{type: :rate_limit}} = Pagination.list(fetch_fn)

      Agent.stop(agent)
    end

    test "returns empty list for no results" do
      fetch_fn = fn _opts -> {:ok, %{"objects" => []}} end

      assert {:ok, []} = Pagination.list(fetch_fn)
    end
  end

  describe "edge cases" do
    test "handles response without objects key gracefully" do
      fetch_fn = fn _opts -> {:ok, %{"data" => []}} end

      result = Pagination.stream(fetch_fn) |> Enum.to_list()
      assert result == []
    end

    test "handles items without id field" do
      fetch_fn = fn _opts ->
        {:ok, %{"objects" => [%{"name" => "no-id"}]}}
      end

      # Should still return items, just no cursor for next page
      result = Pagination.stream(fetch_fn) |> Enum.to_list()
      assert result == [%{"name" => "no-id"}]
    end

    test "uses default limit of 100" do
      fetch_fn = fn opts ->
        assert opts[:limit] == 100
        {:ok, %{"objects" => []}}
      end

      Pagination.stream(fetch_fn) |> Enum.to_list()
    end
  end
end
```

### Success Criteria:

#### Automated Verification:
- [x] All tests pass: `mix test test/braintrust/pagination_test.exs`
- [x] Coverage for pagination module is comprehensive

#### Manual Verification:
- [x] Test names clearly describe behavior
- [x] Edge cases are covered

---

## Phase 3: Client Integration

### Overview
Add convenience functions to the Client module for paginated requests.

### Changes Required:

#### 1. Update `lib/braintrust/client.ex`

Add after the `delete/3` function:

```elixir
@doc """
Makes a paginated GET request, returning a Stream of items.

This is a convenience wrapper around `Braintrust.Pagination.stream/2`
for paginating through list endpoints.

## Options

  * `:limit` - Number of items per page (default: 100)
  * `:starting_after` - Cursor to start pagination from
  * `:unique_by` - Key for duplicate filtering
  * `:params` - Additional query parameters

## Examples

    client = Braintrust.Client.new(api_key: "sk-test")

    client
    |> Braintrust.Client.get_stream("/v1/project", limit: 50)
    |> Stream.take(100)
    |> Enum.to_list()

"""
@spec get_stream(t(), String.t(), keyword()) :: Enumerable.t()
def get_stream(client, path, opts \\ []) do
  {pagination_opts, request_opts} = Keyword.split(opts, [:limit, :starting_after, :unique_by])
  params = Keyword.get(request_opts, :params, [])

  fetch_fn = fn page_opts ->
    merged_params = Keyword.merge(params, page_opts)
    get(client, path, params: merged_params)
  end

  Braintrust.Pagination.stream(fetch_fn, pagination_opts)
end

@doc """
Makes a paginated GET request, returning all items as a list.

This is a convenience wrapper around `Braintrust.Pagination.list/2`.
For large datasets, prefer `get_stream/3`.

## Options

Same as `get_stream/3`.

## Examples

    client = Braintrust.Client.new(api_key: "sk-test")
    {:ok, projects} = Braintrust.Client.get_all(client, "/v1/project")

"""
@spec get_all(t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
def get_all(client, path, opts \\ []) do
  {pagination_opts, request_opts} = Keyword.split(opts, [:limit, :starting_after, :unique_by])
  params = Keyword.get(request_opts, :params, [])

  fetch_fn = fn page_opts ->
    merged_params = Keyword.merge(params, page_opts)
    get(client, path, params: merged_params)
  end

  Braintrust.Pagination.list(fetch_fn, pagination_opts)
end
```

#### 2. Add tests to `test/braintrust/client_test.exs`

Add a new describe block for pagination:

```elixir
describe "get_stream/3" do
  test "returns a stream of items" do
    client = Client.new()

    expect(Req, :request, fn _client, opts ->
      assert opts[:method] == :get
      assert opts[:url] == "/v1/project"
      assert opts[:params][:limit] == 50

      {:ok,
       %Req.Response{
         status: 200,
         body: %{"objects" => [%{"id" => "1"}, %{"id" => "2"}]},
         headers: []
       }}
    end)

    result = Client.get_stream(client, "/v1/project", limit: 50) |> Enum.to_list()
    assert result == [%{"id" => "1"}, %{"id" => "2"}]
  end
end

describe "get_all/3" do
  test "returns all items as a list" do
    client = Client.new()

    expect(Req, :request, fn _client, _opts ->
      {:ok,
       %Req.Response{
         status: 200,
         body: %{"objects" => [%{"id" => "1"}]},
         headers: []
       }}
    end)

    assert {:ok, [%{"id" => "1"}]} = Client.get_all(client, "/v1/project")
  end

  test "returns error on API failure" do
    client = Client.new()

    expect(Req, :request, fn _client, _opts ->
      {:ok, %Req.Response{status: 500, body: %{"error" => "Server error"}, headers: %{}}}
    end)

    assert {:error, %Error{type: :server_error}} = Client.get_all(client, "/v1/project")
  end
end
```

### Success Criteria:

#### Automated Verification:
- [x] All checks pass: `mix quality`
- [x] Tests pass: `mix test`

#### Manual Verification:
- [x] Client functions work correctly with pagination module
- [x] `get_stream/3` returns an Enumerable
- [x] `get_all/3` returns `{:ok, list}` or `{:error, Error.t()}`

---

## Testing Strategy

### Unit Tests
- Stream creation and lazy evaluation
- Multi-page pagination
- Empty results handling
- Error propagation
- Duplicate filtering
- Custom limit and starting_after

### Integration Tests
- Client.get_stream with mock API
- Client.get_all with mock API
- Error handling across pages

### Manual Testing Steps
1. Build a mock fetch function and verify stream behavior in IEx
2. Verify lazy evaluation by checking page fetch counts
3. Test duplicate filtering with overlapping data

## References

- Issue: #9
- Research: `thoughts/shared/research/braintrust_hex_package.md` (lines 636-667)
- Patterns: ExTwilio, ExAws Stream.resource/3 implementations
- Existing code: `lib/braintrust/client.ex`, `lib/braintrust/error.ex`
