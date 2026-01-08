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
