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

  - `Braintrust.Project` - Manage projects
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
