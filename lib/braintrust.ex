defmodule Braintrust do
  @moduledoc """
  Unofficial Elixir SDK for the [Braintrust](https://braintrust.dev) AI evaluation and observability platform.

  > ⚠️ **Work in Progress** - This package is under active development.
  > The API design is being finalized and functionality is not yet implemented.

  ## Installation

  Add `braintrust` to your list of dependencies in `mix.exs`:

      def deps do
        [
          {:braintrust, "~> 0.0.1"}
        ]
      end

  ## Configuration

  Set your API key via environment variable:

      export BRAINTRUST_API_KEY="sk-your-api-key"

  Or configure in your application:

      # config/config.exs
      config :braintrust, api_key: System.get_env("BRAINTRUST_API_KEY")

  ## Resources

  - [Braintrust Documentation](https://www.braintrust.dev/docs)
  - [API Reference](https://www.braintrust.dev/docs/api-reference/introduction)
  - [GitHub Repository](https://github.com/riddler/braintrust)
  """

  @doc """
  Placeholder function - SDK functionality coming soon.

  ## Examples

      iex> Braintrust.hello()
      :world

  """
  def hello do
    :world
  end
end
