# Core HTTP Client and Configuration Implementation Plan

## Overview

Implement the foundational modules for the Braintrust Elixir SDK: `Braintrust.Config`, `Braintrust.Client`, and `Braintrust.Error`. These modules provide configuration management, HTTP communication with retry logic, and standardized error handling that all future resource modules will depend on.

## Current State Analysis

**Existing Code:**
- `lib/braintrust.ex` - Placeholder module with only `hello/0` function
- `mix.exs` - Only has `ex_doc` dependency
- `test/braintrust_test.exs` - Basic test file

**What's Missing:**
- HTTP client (Req library not added)
- JSON encoding (Jason library not added)
- Configuration module
- Error handling module
- Retry logic

### Key Discoveries:
- Req library provides built-in retry with exponential backoff via `retry: :safe_transient` and `retry_delay` options
- Req automatically handles JSON encoding/decoding with `json:` option
- Bearer token auth uses tuple format `{:bearer, token}` in Req
- Braintrust API base URL: `https://api.braintrust.dev` (note: `/v1/` prefix is per-endpoint)

## Desired End State

After implementation:
1. `Braintrust.Config` reads API key from env/config and supports runtime configuration
2. `Braintrust.Client` makes authenticated HTTP requests with proper retry logic
3. `Braintrust.Error` struct enables pattern matching on error types
4. All modules have comprehensive `@spec`, `@type`, and doctests
5. Unit tests pass with mocked HTTP responses

### Verification:
```bash
# All checks pass
mix deps.get
mix compile --warnings-as-errors
mix format --check-formatted
mix test
```

## What We're NOT Doing

- Resource modules (Project, Experiment, Dataset, etc.) - separate ticket
- Pagination module - separate ticket
- OpenTelemetry integration - separate ticket
- LangChain integration - separate ticket
- Streaming support - not needed for core client
- WebSocket support - not needed for core client

## Implementation Approach

Follow idiomatic Elixir patterns:
1. Single error struct with `:type` atom for pattern matching (like Stripity Stripe)
2. Colocate types with their modules
3. Use Req's built-in features for retry, JSON, and auth
4. Support both compile-time config and runtime configuration
5. All public functions return `{:ok, result} | {:error, %Braintrust.Error{}}`

## Phase 1: Add Dependencies

### Overview
Add Req and Jason dependencies to `mix.exs`, plus Mimic for test mocking.

### Changes Required:

#### 1. Update mix.exs dependencies
**File**: `mix.exs`
**Changes**: Add req, jason, and mimic dependencies

```elixir
defp deps do
  [
    {:req, "~> 0.5"},
    {:jason, "~> 1.4"},
    {:mimic, "~> 1.11", only: :test},
    {:ex_doc, "~> 0.35", only: :dev, runtime: false}
  ]
end
```

### Success Criteria:

#### Automated Verification:
- [x] Dependencies install: `mix deps.get`
- [x] Project compiles: `mix compile`

#### Manual Verification:
- [x] Verify `req` and `jason` appear in `mix.lock`

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: Implement Braintrust.Error

### Overview
Create the error struct that all API operations will return on failure. Uses a `:type` atom for pattern matching.

### Changes Required:

#### 1. Create error module
**File**: `lib/braintrust/error.ex`
**Changes**: Create new file with Error struct and helper functions

```elixir
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
```

### Success Criteria:

#### Automated Verification:
- [x] Module compiles: `mix compile --warnings-as-errors`
- [x] Doctests pass: `mix test`
- [x] Format check passes: `mix format --check-formatted`

#### Manual Verification:
- [x] Error struct can be created in IEx: `%Braintrust.Error{type: :not_found, message: "test"}`
- [x] Pattern matching works: `case %Braintrust.Error{type: :not_found} do %{type: :not_found} -> :ok end`

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 3: Implement Braintrust.Config

### Overview
Create configuration module supporting environment variables, compile-time config, and runtime configuration.

### Changes Required:

#### 1. Create config module
**File**: `lib/braintrust/config.ex`
**Changes**: Create new file with configuration functions

```elixir
defmodule Braintrust.Config do
  @moduledoc """
  Configuration management for the Braintrust SDK.

  ## Configuration Sources (in order of precedence)

  1. Runtime options passed to functions
  2. Process dictionary (via `Braintrust.configure/1`)
  3. Application config (via `config :braintrust, ...`)
  4. Environment variables

  ## Configuration Options

  | Option | Type | Default | Description |
  |--------|------|---------|-------------|
  | `:api_key` | string | `BRAINTRUST_API_KEY` env | API key for authentication |
  | `:base_url` | string | `https://api.braintrust.dev` | Base URL for API |
  | `:timeout` | integer | `60_000` | Request timeout in ms |
  | `:max_retries` | integer | `2` | Maximum retry attempts |

  ## Examples

  ### Environment Variable

      export BRAINTRUST_API_KEY="sk-your-api-key"

  ### Application Config

      # config/config.exs
      config :braintrust,
        api_key: System.get_env("BRAINTRUST_API_KEY"),
        timeout: 30_000

  ### Runtime Config

      # Configure for current process
      Braintrust.configure(api_key: "sk-...")

      # Or pass options directly to functions
      Braintrust.Project.list(api_key: "sk-...")

  """

  @default_base_url "https://api.braintrust.dev"
  @default_timeout 60_000
  @default_max_retries 2

  @type config_key :: :api_key | :base_url | :timeout | :max_retries
  @type config_value :: String.t() | pos_integer()

  @doc """
  Gets a configuration value.

  Looks up configuration in order:
  1. Runtime options (if provided)
  2. Process dictionary
  3. Application config
  4. Environment variable (for `:api_key` only)
  5. Default value

  ## Examples

      iex> Braintrust.Config.get(:base_url)
      "https://api.braintrust.dev"

      iex> Braintrust.Config.get(:timeout)
      60000

      iex> Braintrust.Config.get(:base_url, base_url: "https://custom.api.com")
      "https://custom.api.com"

  """
  @spec get(config_key(), keyword()) :: config_value() | nil
  def get(key, opts \\ [])

  def get(:api_key, opts) do
    opts[:api_key] ||
      Process.get(:braintrust_api_key) ||
      Application.get_env(:braintrust, :api_key) ||
      System.get_env("BRAINTRUST_API_KEY")
  end

  def get(:base_url, opts) do
    opts[:base_url] ||
      Process.get(:braintrust_base_url) ||
      Application.get_env(:braintrust, :base_url) ||
      @default_base_url
  end

  def get(:timeout, opts) do
    opts[:timeout] ||
      Process.get(:braintrust_timeout) ||
      Application.get_env(:braintrust, :timeout) ||
      @default_timeout
  end

  def get(:max_retries, opts) do
    opts[:max_retries] ||
      Process.get(:braintrust_max_retries) ||
      Application.get_env(:braintrust, :max_retries) ||
      @default_max_retries
  end

  @doc """
  Gets the API key, raising if not configured.

  ## Examples

      iex> Braintrust.Config.api_key!(api_key: "sk-test123")
      "sk-test123"

  ## Raises

  - `ArgumentError` if no API key is configured

  """
  @spec api_key!(keyword()) :: String.t()
  def api_key!(opts \\ []) do
    case get(:api_key, opts) do
      nil ->
        raise ArgumentError, """
        Braintrust API key not configured.

        Configure using one of:
          1. Environment variable: export BRAINTRUST_API_KEY="sk-..."
          2. Application config: config :braintrust, api_key: "sk-..."
          3. Runtime config: Braintrust.configure(api_key: "sk-...")
          4. Pass directly: Braintrust.Project.list(api_key: "sk-...")
        """

      key ->
        key
    end
  end

  @doc """
  Sets runtime configuration for the current process.

  Configuration set this way takes precedence over application config
  and environment variables, but is overridden by options passed
  directly to functions.

  ## Examples

      iex> Braintrust.Config.configure(api_key: "sk-test", timeout: 30_000)
      :ok
      iex> Braintrust.Config.get(:api_key)
      "sk-test"
      iex> Braintrust.Config.get(:timeout)
      30000

  """
  @spec configure(keyword()) :: :ok
  def configure(opts) do
    if opts[:api_key], do: Process.put(:braintrust_api_key, opts[:api_key])
    if opts[:base_url], do: Process.put(:braintrust_base_url, opts[:base_url])
    if opts[:timeout], do: Process.put(:braintrust_timeout, opts[:timeout])
    if opts[:max_retries], do: Process.put(:braintrust_max_retries, opts[:max_retries])
    :ok
  end

  @doc """
  Clears runtime configuration for the current process.

  ## Examples

      iex> Braintrust.Config.configure(api_key: "sk-test")
      :ok
      iex> Braintrust.Config.clear()
      :ok
      iex> Braintrust.Config.get(:api_key)
      nil

  """
  @spec clear() :: :ok
  def clear do
    Process.delete(:braintrust_api_key)
    Process.delete(:braintrust_base_url)
    Process.delete(:braintrust_timeout)
    Process.delete(:braintrust_max_retries)
    :ok
  end

  @doc """
  Validates an API key format.

  Braintrust API keys use two prefixes:
  - `sk-` for user API keys
  - `bt-st-` for service tokens

  ## Examples

      iex> Braintrust.Config.valid_api_key?("sk-abc123")
      true

      iex> Braintrust.Config.valid_api_key?("bt-st-xyz789")
      true

      iex> Braintrust.Config.valid_api_key?("invalid-key")
      false

      iex> Braintrust.Config.valid_api_key?(nil)
      false

  """
  @spec valid_api_key?(String.t() | nil) :: boolean()
  def valid_api_key?(nil), do: false
  def valid_api_key?("sk-" <> _rest), do: true
  def valid_api_key?("bt-st-" <> _rest), do: true
  def valid_api_key?(_), do: false
end
```

### Success Criteria:

#### Automated Verification:
- [x] Module compiles: `mix compile --warnings-as-errors`
- [x] Doctests pass: `mix test`
- [x] Format check passes: `mix format --check-formatted`

#### Manual Verification:
- [x] In IEx, `Braintrust.Config.get(:base_url)` returns default URL
- [x] In IEx, `Braintrust.Config.configure(api_key: "sk-test")` and then `Braintrust.Config.get(:api_key)` returns "sk-test"
- [x] In IEx, `Braintrust.Config.api_key!()` raises when no key configured

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 4: Implement Braintrust.Client

### Overview
Create the HTTP client using Req with bearer token auth, JSON handling, timeouts, and retry logic with exponential backoff.

### Changes Required:

#### 1. Create client module
**File**: `lib/braintrust/client.ex`
**Changes**: Create new file with HTTP client

```elixir
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
```

### Success Criteria:

#### Automated Verification:
- [x] Module compiles: `mix compile --warnings-as-errors`
- [x] Format check passes: `mix format --check-formatted`
- [x] Tests pass: `mix test`

#### Manual Verification:
- [x] In IEx, can create client: `Braintrust.Client.new(api_key: "sk-test")` returns Req.Request struct
- [x] Verify user-agent header is set correctly

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 5: Add Public API to Main Module

### Overview
Update the main `Braintrust` module to expose `configure/1` for runtime configuration.

### Changes Required:

#### 1. Update main module
**File**: `lib/braintrust.ex`
**Changes**: Replace placeholder with public API

```elixir
defmodule Braintrust do
  @moduledoc """
  Unofficial Elixir SDK for the [Braintrust](https://braintrust.dev) AI evaluation and observability platform.

  ## Installation

  Add `braintrust` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:braintrust, "~> 0.1.0"}
        ]
      end

  ## Configuration

  Set your API key via environment variable:

      export BRAINTRUST_API_KEY="sk-your-api-key"

  Or configure in your application:

      # config/config.exs
      config :braintrust,
        api_key: System.get_env("BRAINTRUST_API_KEY"),
        timeout: 30_000

  Or configure at runtime:

      Braintrust.configure(api_key: "sk-your-api-key")

  ## Usage

  See the individual resource modules for API operations:

  - `Braintrust.Project` - Manage projects (coming soon)
  - `Braintrust.Experiment` - Run experiments (coming soon)
  - `Braintrust.Dataset` - Manage datasets (coming soon)
  - `Braintrust.Log` - Log traces and spans (coming soon)

  ## Resources

  - [Braintrust Documentation](https://www.braintrust.dev/docs)
  - [API Reference](https://www.braintrust.dev/docs/api-reference/introduction)
  - [GitHub Repository](https://github.com/riddler/braintrust)
  """

  alias Braintrust.Config

  @doc """
  Configures the Braintrust SDK for the current process.

  Configuration set via this function takes precedence over application
  config and environment variables, but is overridden by options passed
  directly to API functions.

  ## Options

  - `:api_key` - API key for authentication (prefix: `sk-` or `bt-st-`)
  - `:base_url` - Base URL for API (default: `https://api.braintrust.dev`)
  - `:timeout` - Request timeout in milliseconds (default: 60000)
  - `:max_retries` - Maximum retry attempts (default: 2)

  ## Examples

      iex> Braintrust.configure(api_key: "sk-test123")
      :ok

      iex> Braintrust.configure(api_key: "sk-test", timeout: 30_000, max_retries: 3)
      :ok

  """
  @spec configure(keyword()) :: :ok
  defdelegate configure(opts), to: Config
end
```

### Success Criteria:

#### Automated Verification:
- [x] Module compiles: `mix compile --warnings-as-errors`
- [x] Format check passes: `mix format --check-formatted`
- [x] Doctests pass: `mix test`

#### Manual Verification:
- [x] In IEx, `Braintrust.configure(api_key: "sk-test")` returns `:ok`

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 6: Write Unit Tests

### Overview
Create comprehensive unit tests using Mimic to mock HTTP responses.

### Changes Required:

#### 1. Update test helper
**File**: `test/test_helper.exs`
**Changes**: Add Mimic setup

```elixir
ExUnit.start()
Mimic.copy(Req)
```

#### 2. Create error tests
**File**: `test/braintrust/error_test.exs`
**Changes**: Create new test file

```elixir
defmodule Braintrust.ErrorTest do
  use ExUnit.Case, async: true
  doctest Braintrust.Error

  alias Braintrust.Error

  describe "new/3" do
    test "creates error with required fields" do
      error = Error.new(:not_found, "Resource not found")

      assert error.type == :not_found
      assert error.message == "Resource not found"
      assert error.code == nil
      assert error.status == nil
      assert error.retry_after == nil
    end

    test "creates error with optional fields" do
      error = Error.new(:rate_limit, "Too many requests",
        status: 429,
        code: "rate_limit_exceeded",
        retry_after: 5000
      )

      assert error.type == :rate_limit
      assert error.message == "Too many requests"
      assert error.status == 429
      assert error.code == "rate_limit_exceeded"
      assert error.retry_after == 5000
    end
  end

  describe "retryable?/1" do
    test "returns true for retryable error types" do
      assert Error.retryable?(Error.new(:conflict, "Conflict"))
      assert Error.retryable?(Error.new(:rate_limit, "Rate limited"))
      assert Error.retryable?(Error.new(:server_error, "Server error"))
      assert Error.retryable?(Error.new(:timeout, "Timeout"))
      assert Error.retryable?(Error.new(:connection, "Connection error"))
    end

    test "returns false for non-retryable error types" do
      refute Error.retryable?(Error.new(:bad_request, "Bad request"))
      refute Error.retryable?(Error.new(:authentication, "Unauthorized"))
      refute Error.retryable?(Error.new(:permission_denied, "Forbidden"))
      refute Error.retryable?(Error.new(:not_found, "Not found"))
      refute Error.retryable?(Error.new(:unprocessable_entity, "Invalid"))
    end
  end

  describe "type_from_status/1" do
    test "maps HTTP status codes to error types" do
      assert Error.type_from_status(400) == :bad_request
      assert Error.type_from_status(401) == :authentication
      assert Error.type_from_status(403) == :permission_denied
      assert Error.type_from_status(404) == :not_found
      assert Error.type_from_status(409) == :conflict
      assert Error.type_from_status(422) == :unprocessable_entity
      assert Error.type_from_status(429) == :rate_limit
      assert Error.type_from_status(500) == :server_error
      assert Error.type_from_status(502) == :server_error
      assert Error.type_from_status(503) == :server_error
    end

    test "maps unknown 4xx to bad_request" do
      assert Error.type_from_status(418) == :bad_request
    end
  end
end
```

#### 3. Create config tests
**File**: `test/braintrust/config_test.exs`
**Changes**: Create new test file

```elixir
defmodule Braintrust.ConfigTest do
  use ExUnit.Case, async: false
  doctest Braintrust.Config

  alias Braintrust.Config

  setup do
    # Clean up any process-level config
    Config.clear()
    # Clean up any app-level config
    Application.delete_env(:braintrust, :api_key)
    Application.delete_env(:braintrust, :base_url)
    Application.delete_env(:braintrust, :timeout)
    Application.delete_env(:braintrust, :max_retries)
    :ok
  end

  describe "get/2" do
    test "returns default base_url" do
      assert Config.get(:base_url) == "https://api.braintrust.dev"
    end

    test "returns default timeout" do
      assert Config.get(:timeout) == 60_000
    end

    test "returns default max_retries" do
      assert Config.get(:max_retries) == 2
    end

    test "runtime opts take precedence" do
      Config.configure(base_url: "https://process.local")
      Application.put_env(:braintrust, :base_url, "https://app.local")

      assert Config.get(:base_url, base_url: "https://opts.local") == "https://opts.local"
    end

    test "process config takes precedence over app config" do
      Config.configure(base_url: "https://process.local")
      Application.put_env(:braintrust, :base_url, "https://app.local")

      assert Config.get(:base_url) == "https://process.local"
    end

    test "app config takes precedence over defaults" do
      Application.put_env(:braintrust, :timeout, 15_000)

      assert Config.get(:timeout) == 15_000
    end
  end

  describe "api_key!/1" do
    test "returns api_key from opts" do
      assert Config.api_key!(api_key: "sk-opts") == "sk-opts"
    end

    test "returns api_key from process config" do
      Config.configure(api_key: "sk-process")
      assert Config.api_key!() == "sk-process"
    end

    test "returns api_key from app config" do
      Application.put_env(:braintrust, :api_key, "sk-app")
      assert Config.api_key!() == "sk-app"
    end

    test "raises when no api_key configured" do
      assert_raise ArgumentError, ~r/API key not configured/, fn ->
        Config.api_key!()
      end
    end
  end

  describe "configure/1" do
    test "sets process-level config" do
      Config.configure(
        api_key: "sk-test",
        base_url: "https://custom.local",
        timeout: 5000,
        max_retries: 5
      )

      assert Config.get(:api_key) == "sk-test"
      assert Config.get(:base_url) == "https://custom.local"
      assert Config.get(:timeout) == 5000
      assert Config.get(:max_retries) == 5
    end

    test "only sets provided options" do
      Config.configure(api_key: "sk-test")

      assert Config.get(:api_key) == "sk-test"
      # Others should still be defaults
      assert Config.get(:base_url) == "https://api.braintrust.dev"
    end
  end

  describe "clear/0" do
    test "clears process-level config" do
      Config.configure(api_key: "sk-test", timeout: 5000)
      Config.clear()

      assert Config.get(:api_key) == nil
      assert Config.get(:timeout) == 60_000
    end
  end

  describe "valid_api_key?/1" do
    test "returns true for user API keys" do
      assert Config.valid_api_key?("sk-abc123")
      assert Config.valid_api_key?("sk-very-long-key-here")
    end

    test "returns true for service tokens" do
      assert Config.valid_api_key?("bt-st-abc123")
      assert Config.valid_api_key?("bt-st-very-long-token")
    end

    test "returns false for invalid keys" do
      refute Config.valid_api_key?(nil)
      refute Config.valid_api_key?("")
      refute Config.valid_api_key?("invalid")
      refute Config.valid_api_key?("api-key")
    end
  end
end
```

#### 4. Create client tests
**File**: `test/braintrust/client_test.exs`
**Changes**: Create new test file with mocked HTTP

```elixir
defmodule Braintrust.ClientTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Braintrust.{Client, Config, Error}

  setup do
    Config.configure(api_key: "sk-test")
    :ok
  end

  describe "new/1" do
    test "creates a Req.Request struct" do
      client = Client.new()
      assert %Req.Request{} = client
    end

    test "uses configured base_url" do
      client = Client.new(base_url: "https://custom.api.com")
      assert client.options.base_url == "https://custom.api.com"
    end

    test "raises when no api_key configured" do
      Config.clear()

      assert_raise ArgumentError, ~r/API key not configured/, fn ->
        Client.new()
      end
    end
  end

  describe "get/3" do
    test "returns decoded JSON on success" do
      client = Client.new()
      response_body = %{"id" => "proj_123", "name" => "test"}

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :get
        assert opts[:url] == "/v1/project"
        {:ok, %Req.Response{status: 200, body: response_body, headers: []}}
      end)

      assert {:ok, ^response_body} = Client.get(client, "/v1/project")
    end

    test "returns error on 404" do
      client = Client.new()
      error_body = %{"error" => %{"message" => "Project not found"}}

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 404, body: error_body, headers: []}}
      end)

      assert {:error, %Error{type: :not_found, message: "Project not found"}} =
               Client.get(client, "/v1/project/invalid")
    end

    test "returns error with retry_after on 429" do
      client = Client.new()
      error_body = %{"error" => %{"message" => "Rate limit exceeded"}}

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{
          status: 429,
          body: error_body,
          headers: [{"retry-after", "5"}]
        }}
      end)

      assert {:error, %Error{type: :rate_limit, retry_after: 5000}} =
               Client.get(client, "/v1/project")
    end

    test "returns timeout error" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      assert {:error, %Error{type: :timeout}} = Client.get(client, "/v1/project")
    end

    test "returns connection error" do
      client = Client.new()

      expect(Req, :request, fn _client, _opts ->
        {:error, %Req.TransportError{reason: :econnrefused}}
      end)

      assert {:error, %Error{type: :connection}} = Client.get(client, "/v1/project")
    end
  end

  describe "post/4" do
    test "sends JSON body and returns decoded response" do
      client = Client.new()
      request_body = %{name: "new-project"}
      response_body = %{"id" => "proj_123", "name" => "new-project"}

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :post
        assert opts[:url] == "/v1/project"
        assert opts[:json] == request_body
        {:ok, %Req.Response{status: 201, body: response_body, headers: []}}
      end)

      assert {:ok, ^response_body} = Client.post(client, "/v1/project", request_body)
    end

    test "returns error on 400 with error message" do
      client = Client.new()
      error_body = %{"error" => %{"message" => "Name is required", "code" => "validation_error"}}

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 400, body: error_body, headers: []}}
      end)

      assert {:error, %Error{
        type: :bad_request,
        message: "Name is required",
        code: "validation_error",
        status: 400
      }} = Client.post(client, "/v1/project", %{})
    end
  end

  describe "patch/4" do
    test "sends JSON body for partial update" do
      client = Client.new()
      request_body = %{name: "updated-name"}
      response_body = %{"id" => "proj_123", "name" => "updated-name"}

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :patch
        assert opts[:json] == request_body
        {:ok, %Req.Response{status: 200, body: response_body, headers: []}}
      end)

      assert {:ok, ^response_body} = Client.patch(client, "/v1/project/proj_123", request_body)
    end
  end

  describe "delete/3" do
    test "returns success on 200" do
      client = Client.new()
      response_body = %{"id" => "proj_123", "deleted" => true}

      expect(Req, :request, fn _client, opts ->
        assert opts[:method] == :delete
        {:ok, %Req.Response{status: 200, body: response_body, headers: []}}
      end)

      assert {:ok, ^response_body} = Client.delete(client, "/v1/project/proj_123")
    end

    test "returns error on 403" do
      client = Client.new()
      error_body = %{"error" => %{"message" => "Permission denied"}}

      expect(Req, :request, fn _client, _opts ->
        {:ok, %Req.Response{status: 403, body: error_body, headers: []}}
      end)

      assert {:error, %Error{type: :permission_denied}} =
               Client.delete(client, "/v1/project/proj_123")
    end
  end
end
```

#### 5. Update main test file
**File**: `test/braintrust_test.exs`
**Changes**: Update to test main module

```elixir
defmodule BraintrustTest do
  use ExUnit.Case, async: false
  doctest Braintrust

  alias Braintrust.Config

  setup do
    Config.clear()
    :ok
  end

  describe "configure/1" do
    test "delegates to Config.configure/1" do
      assert :ok = Braintrust.configure(api_key: "sk-test")
      assert Config.get(:api_key) == "sk-test"
    end
  end
end
```

### Success Criteria:

#### Automated Verification:
- [x] All tests pass: `mix test`
- [x] Format check passes: `mix format --check-formatted`
- [x] No compiler warnings: `mix compile --warnings-as-errors`

#### Manual Verification:
- [ ] Run `mix test --trace` to see all tests passing with names

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 7: Integration Test (Optional)

### Overview
Test against real Braintrust API (requires valid API key).

### Changes Required:

#### 1. Create integration test
**File**: `test/integration/client_integration_test.exs`
**Changes**: Create integration test (skipped by default)

```elixir
defmodule Braintrust.ClientIntegrationTest do
  @moduledoc """
  Integration tests against real Braintrust API.

  Run with: BRAINTRUST_API_KEY=sk-... mix test test/integration --include integration
  """
  use ExUnit.Case, async: false

  alias Braintrust.{Client, Config}

  @moduletag :integration

  setup do
    case System.get_env("BRAINTRUST_API_KEY") do
      nil ->
        :ok

      key ->
        Config.configure(api_key: key)
        :ok
    end
  end

  @tag :integration
  test "can list projects" do
    client = Client.new()
    result = Client.get(client, "/v1/project")

    case result do
      {:ok, %{"objects" => objects}} ->
        assert is_list(objects)

      {:error, error} ->
        flunk("Expected success, got error: #{inspect(error)}")
    end
  end
end
```

### Success Criteria:

#### Automated Verification:
- [ ] Test file compiles: `mix compile --warnings-as-errors`

#### Manual Verification:
- [ ] With valid API key: `BRAINTRUST_API_KEY=sk-... mix test test/integration --include integration`

**Implementation Note**: This phase is optional and only for verifying real API connectivity.

---

## Testing Strategy

### Unit Tests:
- `Braintrust.Error` - Struct creation, type mapping, retryable detection
- `Braintrust.Config` - Configuration precedence, validation, runtime config
- `Braintrust.Client` - HTTP methods, error handling, retry logic (mocked)

### Integration Tests:
- Real API call to list projects (requires API key)

### Doctests:
All modules include comprehensive doctests that serve as both documentation and tests.

### Manual Testing Steps:
1. Start IEx: `iex -S mix`
2. Test config: `Braintrust.configure(api_key: "sk-test")`
3. Test client creation: `Braintrust.Client.new()`
4. Test error creation: `Braintrust.Error.new(:not_found, "test")`

## Performance Considerations

- Req uses Finch for connection pooling by default
- Exponential backoff prevents thundering herd on failures
- Configurable timeouts allow tuning for different use cases

## Migration Notes

N/A - This is greenfield implementation.

## References

- Source issue: GitHub issue #5
- Research doc: `thoughts/shared/research/braintrust_hex_package.md`
- Braintrust API: https://www.braintrust.dev/docs/api-reference/introduction
- Req library: https://hexdocs.pm/req/Req.html
