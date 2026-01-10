defmodule Braintrust.TestHelpers do
  @moduledoc false
  # Shared test utilities for Braintrust test suite

  @doc """
  Creates a mock Req stub that simulates pagination with an Agent.

  Returns a function that can be used with Mimic's stub/2.

  ## Parameters
    * `first_response` - The response body for the first page
    * `empty_response` - The response body for empty pages (default: %{"objects" => []})

  ## Example

      {:ok, agent} = Agent.start_link(fn -> 0 end)

      stub(Req, :request, paginated_stub(
        agent,
        %{"objects" => [%{"id" => "1"}]},
        %{"objects" => []}
      ))
  """
  @spec paginated_stub(pid(), map(), map()) :: (any(), any() -> {:ok, Req.Response.t()})
  def paginated_stub(agent, first_response, empty_response \\ %{"objects" => []}) do
    fn _client, _opts ->
      page = Agent.get_and_update(agent, fn n -> {n, n + 1} end)

      case page do
        0 ->
          {:ok, %Req.Response{status: 200, body: first_response, headers: []}}

        _page ->
          {:ok, %Req.Response{status: 200, body: empty_response, headers: []}}
      end
    end
  end

  @doc """
  Creates and starts an Agent for pagination testing.

  Returns `{:ok, agent}` which can be used with paginated_stub/3.
  """
  @spec start_pagination_agent() :: {:ok, pid()}
  def start_pagination_agent do
    Agent.start_link(fn -> 0 end)
  end
end
