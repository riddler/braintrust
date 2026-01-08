defmodule Braintrust.Error do
  @moduledoc """
  Error struct for Braintrust API errors.

  All API functions return `{:error, %Braintrust.Error{}}` on failure,
  allowing pattern matching on the `:type` field.

  ## Error Types

  | Type | HTTP Status | Retryable? | Description |
  |------|-------------|------------|-------------|
  | `:bad_request` | 400 | No | Invalid request parameters |
  | `:authentication` | 401 | No | Missing or invalid API key |
  | `:permission_denied` | 403 | No | Insufficient permissions |
  | `:not_found` | 404 | No | Resource not found |
  | `:conflict` | 409 | Yes | Conflict error |
  | `:unprocessable_entity` | 422 | No | Validation error |
  | `:rate_limit` | 429 | Yes | Rate limit exceeded |
  | `:server_error` | 5xx | Yes | Server error |
  | `:timeout` | N/A | Yes | Request timeout |
  | `:connection` | N/A | Yes | Network/connection error |

  ## Examples

      case Braintrust.Project.get("invalid-id") do
        {:ok, project} ->
          handle_project(project)

        {:error, %Braintrust.Error{type: :not_found}} ->
          handle_not_found()

        {:error, %Braintrust.Error{type: :rate_limit, retry_after: ms}} ->
          Process.sleep(ms)
          retry()

        {:error, %Braintrust.Error{} = error} ->
          Logger.error("API error: \#{error.message}")
      end

  """

  @type error_type ::
          :bad_request
          | :authentication
          | :permission_denied
          | :not_found
          | :conflict
          | :unprocessable_entity
          | :rate_limit
          | :server_error
          | :timeout
          | :connection

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          code: String.t() | nil,
          status: pos_integer() | nil,
          retry_after: pos_integer() | nil
        }

  defstruct [:type, :message, :code, :status, :retry_after]

  @doc """
  Creates a new error struct.

  ## Examples

      iex> error = Braintrust.Error.new(:not_found, "Project not found")
      iex> error.type
      :not_found
      iex> error.message
      "Project not found"

      iex> error = Braintrust.Error.new(:rate_limit, "Too many requests", retry_after: 5000)
      iex> error.retry_after
      5000

  """
  @spec new(error_type(), String.t(), keyword()) :: t()
  def new(type, message, opts \\ []) do
    %__MODULE__{
      type: type,
      message: message,
      code: opts[:code],
      status: opts[:status],
      retry_after: opts[:retry_after]
    }
  end

  @doc """
  Returns whether the error is retryable.

  Retryable errors are those that may succeed on retry:
  - `:conflict` - Temporary conflict
  - `:rate_limit` - Rate limit will reset
  - `:server_error` - Server may recover
  - `:timeout` - Network may recover
  - `:connection` - Connection may be restored

  ## Examples

      iex> error = Braintrust.Error.new(:rate_limit, "Too many requests")
      iex> Braintrust.Error.retryable?(error)
      true

      iex> error = Braintrust.Error.new(:not_found, "Resource not found")
      iex> Braintrust.Error.retryable?(error)
      false

  """
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{type: type}) do
    type in [:conflict, :rate_limit, :server_error, :timeout, :connection]
  end

  @doc """
  Converts an HTTP status code to an error type.

  ## Examples

      iex> Braintrust.Error.type_from_status(404)
      :not_found

      iex> Braintrust.Error.type_from_status(500)
      :server_error

      iex> Braintrust.Error.type_from_status(503)
      :server_error

  """
  @spec type_from_status(pos_integer()) :: error_type()
  def type_from_status(400), do: :bad_request
  def type_from_status(401), do: :authentication
  def type_from_status(403), do: :permission_denied
  def type_from_status(404), do: :not_found
  def type_from_status(409), do: :conflict
  def type_from_status(422), do: :unprocessable_entity
  def type_from_status(429), do: :rate_limit
  def type_from_status(status) when status >= 500, do: :server_error
  def type_from_status(_), do: :bad_request
end
