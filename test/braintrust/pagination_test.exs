defmodule Braintrust.PaginationTest do
  use ExUnit.Case, async: true

  alias Braintrust.{Error, Pagination}

  # Helper to create a fetch function that tracks call count
  defp paginated_fetch(pages) do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    fetch_fn = fn opts ->
      page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

      case Enum.at(pages, page) do
        nil ->
          {:ok, %{"objects" => []}}

        {:error, _reason} = error ->
          error

        {:check, check_fn, result} ->
          check_fn.(opts)
          result

        items ->
          {:ok, %{"objects" => items}}
      end
    end

    {fetch_fn, agent}
  end

  describe "stream/2" do
    test "returns items from single page" do
      {fetch_fn, agent} =
        paginated_fetch([
          [%{"id" => "1"}, %{"id" => "2"}]
        ])

      result = Pagination.stream(fetch_fn) |> Enum.to_list()
      assert result == [%{"id" => "1"}, %{"id" => "2"}]

      Agent.stop(agent)
    end

    test "paginates through multiple pages" do
      {fetch_fn, agent} =
        paginated_fetch([
          [%{"id" => "a"}, %{"id" => "b"}],
          [%{"id" => "c"}, %{"id" => "d"}]
        ])

      result = Pagination.stream(fetch_fn, limit: 2) |> Enum.to_list()
      assert result == [%{"id" => "a"}, %{"id" => "b"}, %{"id" => "c"}, %{"id" => "d"}]

      Agent.stop(agent)
    end

    test "passes correct cursors between pages" do
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
            {:ok, %{"objects" => [%{"id" => "c"}]}}

          2 ->
            assert opts[:starting_after] == "c"
            {:ok, %{"objects" => []}}
        end
      end

      result = Pagination.stream(fetch_fn, limit: 2) |> Enum.to_list()
      assert result == [%{"id" => "a"}, %{"id" => "b"}, %{"id" => "c"}]

      Agent.stop(agent)
    end

    test "handles empty first page" do
      fetch_fn = fn _opts -> {:ok, %{"objects" => []}} end

      result = Pagination.stream(fetch_fn) |> Enum.to_list()
      assert result == []
    end

    test "respects starting_after option" do
      {:ok, agent} = Agent.start_link(fn -> 0 end)

      fetch_fn = fn opts ->
        page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

        case page do
          0 ->
            assert opts[:starting_after] == "cursor123"
            {:ok, %{"objects" => [%{"id" => "x"}]}}

          1 ->
            assert opts[:starting_after] == "x"
            {:ok, %{"objects" => []}}
        end
      end

      result = Pagination.stream(fetch_fn, starting_after: "cursor123") |> Enum.to_list()
      assert result == [%{"id" => "x"}]

      Agent.stop(agent)
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
      {fetch_fn, agent} =
        paginated_fetch([
          [%{"id" => "1"}, %{"id" => "2"}],
          [%{"id" => "2"}, %{"id" => "3"}]
        ])

      result = Pagination.stream(fetch_fn, unique_by: :id) |> Enum.to_list()
      assert result == [%{"id" => "1"}, %{"id" => "2"}, %{"id" => "3"}]

      Agent.stop(agent)
    end

    test "Stream.take works correctly and stops fetching" do
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
      {fetch_fn, agent} =
        paginated_fetch([
          [%{"id" => "1"}],
          [%{"id" => "2"}]
        ])

      assert {:ok, items} = Pagination.list(fetch_fn)
      assert items == [%{"id" => "1"}, %{"id" => "2"}]

      Agent.stop(agent)
    end

    test "returns error when fetch fails on first page" do
      fetch_fn = fn _opts ->
        {:error, Error.new(:server_error, "API error")}
      end

      assert {:error, %Error{type: :server_error}} = Pagination.list(fetch_fn)
    end

    test "returns error when fetch fails on subsequent page" do
      {fetch_fn, agent} =
        paginated_fetch([
          [%{"id" => "1"}],
          {:error, Error.new(:rate_limit, "Rate limited")}
        ])

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

    test "handles items without id field - stops after first page" do
      # Items without "id" field mean no cursor, so pagination stops
      {fetch_fn, agent} =
        paginated_fetch([
          [%{"name" => "no-id"}]
        ])

      result = Pagination.stream(fetch_fn) |> Enum.to_list()
      assert result == [%{"name" => "no-id"}]

      # Verify only one fetch was made (no second page attempted)
      assert Agent.get(agent, & &1) == 1

      Agent.stop(agent)
    end

    test "uses default limit of 100" do
      {:ok, agent} = Agent.start_link(fn -> nil end)

      fetch_fn = fn opts ->
        Agent.update(agent, fn _prev -> opts[:limit] end)
        {:ok, %{"objects" => []}}
      end

      Pagination.stream(fetch_fn) |> Enum.to_list()

      assert Agent.get(agent, & &1) == 100

      Agent.stop(agent)
    end
  end
end
