defmodule Braintrust.Client do
  @moduledoc """
  HTTP client for the Braintrust API.

  This module handles all HTTP communication with the Braintrust API,
  including authentication, JSON encoding/decoding, timeouts, and
  automatic retry with exponential backoff.

  ## Usage

  The client is typically used internally by resource modules, but can
  be used directly for custom API calls:

      # Create a client
      client = Braintrust.Client.new(api_key: "sk-...")

      # Make requests
      {:ok, body} = Braintrust.Client.get(client, "/v1/project")
      {:ok, body} = Braintrust.Client.post(client, "/v1/project", %{name: "my-project"})

  ## Retry Behavior

  The client automatically retries requests that fail with:
  - 408 Request Timeout
  - 409 Conflict
  - 429 Rate Limit (respects Retry-After header)
  - 5xx Server Errors
  - Connection/timeout errors

  Default: 2 retries with exponential backoff (1s, 2s, 4s).

  """

  alias Braintrust.{Config, Error}

  @type t :: Req.Request.t()

  @doc """
  Creates a new HTTP client.

  ## Options

  All options from `Braintrust.Config` are supported:
  - `:api_key` - API key for authentication
  - `:base_url` - Base URL for API requests
  - `:timeout` - Request timeout in milliseconds
  - `:max_retries` - Maximum number of retry attempts

  ## Examples

      iex> client = Braintrust.Client.new(api_key: "sk-test123")
      iex> is_struct(client, Req.Request)
      true

  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    api_key = Config.api_key!(opts)
    base_url = Config.get(:base_url, opts)
    timeout = Config.get(:timeout, opts)
    max_retries = Config.get(:max_retries, opts)

    Req.new(
      base_url: base_url,
      auth: {:bearer, api_key},
      headers: [
        {"content-type", "application/json"},
        {"accept", "application/json"},
        {"user-agent", user_agent()}
      ],
      receive_timeout: timeout,
      connect_options: [
        timeout: 10_000,
        protocols: [:http1, :http2]
      ],
      retry: &retry_policy/2,
      max_retries: max_retries,
      retry_delay: &exponential_backoff/1,
      retry_log_level: :warning
    )
  end

  @doc """
  Makes a GET request.

  ## Examples

      client = Braintrust.Client.new(api_key: "sk-test")
      {:ok, projects} = Braintrust.Client.get(client, "/v1/project")

  """
  @spec get(t(), String.t(), keyword()) :: {:ok, map() | list()} | {:error, Error.t()}
  def get(client, path, opts \\ []) do
    request(client, :get, path, opts)
  end

  @doc """
  Makes a POST request.

  ## Examples

      client = Braintrust.Client.new(api_key: "sk-test")
      {:ok, project} = Braintrust.Client.post(client, "/v1/project", %{name: "my-project"})

  """
  @spec post(t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def post(client, path, body, opts \\ []) do
    request(client, :post, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Makes a PATCH request.

  ## Examples

      client = Braintrust.Client.new(api_key: "sk-test")
      {:ok, project} = Braintrust.Client.patch(client, "/v1/project/123", %{name: "new-name"})

  """
  @spec patch(t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def patch(client, path, body, opts \\ []) do
    request(client, :patch, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Makes a DELETE request.

  ## Examples

      client = Braintrust.Client.new(api_key: "sk-test")
      {:ok, _} = Braintrust.Client.delete(client, "/v1/project/123")

  """
  @spec delete(t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def delete(client, path, opts \\ []) do
    request(client, :delete, path, opts)
  end

  # Private Functions

  defp request(client, method, path, opts) do
    req_opts = [method: method, url: path] ++ opts

    case Req.request(client, req_opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %{status: status, body: body, headers: headers}} ->
        {:error, build_error(status, body, headers)}

      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, Error.new(:timeout, "Request timed out")}

      {:error, %Req.TransportError{reason: reason}} ->
        {:error, Error.new(:connection, "Connection error: #{inspect(reason)}")}

      {:error, exception} ->
        {:error, Error.new(:connection, "Unexpected error: #{Exception.message(exception)}")}
    end
  end

  defp build_error(status, body, headers) do
    type = Error.type_from_status(status)
    message = extract_message(body)
    code = extract_code(body)
    retry_after = extract_retry_after(headers)

    Error.new(type, message,
      status: status,
      code: code,
      retry_after: retry_after
    )
  end

  defp extract_message(body) when is_map(body) do
    # Braintrust error format: {"error": {"message": "...", "type": "...", "code": "..."}}
    get_in(body, ["error", "message"]) ||
      body["message"] ||
      body["error"] ||
      "Request failed"
  end

  defp extract_message(body) when is_binary(body), do: body
  defp extract_message(_), do: "Request failed"

  defp extract_code(body) when is_map(body) do
    get_in(body, ["error", "code"]) || body["code"]
  end

  defp extract_code(_), do: nil

  defp extract_retry_after(headers) do
    case List.keyfind(headers, "retry-after", 0) do
      {"retry-after", value} ->
        case Integer.parse(value) do
          {seconds, _} -> seconds * 1000
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp retry_policy(_request, response_or_error) do
    case response_or_error do
      # Rate limit - use Retry-After header if present
      %{status: 429, headers: headers} ->
        case extract_retry_after(headers) do
          nil -> true
          ms -> {:delay, ms}
        end

      # Retryable status codes
      %{status: status} when status in [408, 409] ->
        true

      %{status: status} when status >= 500 ->
        true

      # Connection/timeout errors are retryable
      %Req.TransportError{} ->
        true

      # Don't retry other errors
      _ ->
        false
    end
  end

  defp exponential_backoff(attempt) do
    # 1000ms, 2000ms, 4000ms, ...
    trunc(:math.pow(2, attempt) * 1000)
  end

  defp user_agent do
    version = Application.spec(:braintrust, :vsn) || "0.0.0"
    "braintrust-elixir/#{version}"
  end
end
