# Braintrust

> ⚠️ **Work in Progress** - This package is under active development. The README below describes the target API design and may not reflect current functionality.

An unofficial Elixir client for the [Braintrust](https://braintrust.dev) AI evaluation and observability platform.

Braintrust is an end-to-end platform for evaluating, monitoring, and improving AI applications. This Hex package provides Elixir/Phoenix applications with access to Braintrust's REST API for managing projects, experiments, datasets, logs, and prompts.

## Installation

Add `braintrust` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:braintrust, "~> 0.0.1"}
  ]
end
```

## Configuration

Set your API key via environment variable:

```bash
export BRAINTRUST_API_KEY="sk-your-api-key"
```

Or configure in your application:

```elixir
# config/config.exs
config :braintrust, api_key: System.get_env("BRAINTRUST_API_KEY")

# Or at runtime
Braintrust.configure(api_key: "sk-xxx")
```

API keys can be created at [braintrust.dev/app/settings](https://www.braintrust.dev/app/settings?subroute=api-keys).

## Usage

### Projects

```elixir
# List all projects
{:ok, projects} = Braintrust.Project.list()

# Create a project
{:ok, project} = Braintrust.Project.create(%{name: "my-project"})

# Get a project by ID
{:ok, project} = Braintrust.Project.get(project_id)

# Delete a project
:ok = Braintrust.Project.delete(project_id)
```

### Logging Traces

Log production traces for observability:

```elixir
{:ok, _} = Braintrust.Log.insert(project_id, %{
  events: [
    %{
      input: %{messages: [%{role: "user", content: "Hello"}]},
      output: "Hi there!",
      scores: %{quality: 0.9},
      metadata: %{model: "gpt-4"}
    }
  ]
})
```

### Experiments

Run evaluations and track results:

```elixir
# Create an experiment
{:ok, experiment} = Braintrust.Experiment.create(project_id, %{name: "baseline-v1"})

# Insert experiment events
{:ok, _} = Braintrust.Experiment.insert(experiment_id, %{
  events: [
    %{
      input: %{question: "What is 2+2?"},
      output: "4",
      scores: %{accuracy: 1.0}
    }
  ]
})

# Get experiment summary with scores
{:ok, summary} = Braintrust.Experiment.summarize(experiment_id)
```

### Datasets

Manage test data for evaluations:

```elixir
# Create a dataset
{:ok, dataset} = Braintrust.Dataset.create(project_id, %{name: "test-cases"})

# Insert test cases
{:ok, _} = Braintrust.Dataset.insert(dataset_id, %{
  events: [
    %{input: %{question: "What is 2+2?"}, expected: "4"},
    %{input: %{question: "What is 3+3?"}, expected: "6"}
  ]
})

# Fetch dataset records
{:ok, records} = Braintrust.Dataset.fetch(dataset_id)
```

### Prompts

Version-controlled prompt management:

```elixir
# List prompts
{:ok, prompts} = Braintrust.Prompt.list(project_name: "my-project")

# Get a prompt by ID
{:ok, prompt} = Braintrust.Prompt.get(prompt_id)
```

### Pagination

Results are automatically paginated. Use streams for lazy iteration:

```elixir
Braintrust.Project.list()
|> Braintrust.Pagination.stream()
|> Stream.take(100)
|> Enum.to_list()
```

### Error Handling

All API functions return `{:ok, result}` or `{:error, %Braintrust.Error{}}`:

```elixir
case Braintrust.Project.get(project_id) do
  {:ok, project} ->
    handle_project(project)

  {:error, %Braintrust.Error{type: :not_found}} ->
    handle_not_found()

  {:error, %Braintrust.Error{type: :rate_limit, retry_after: ms}} ->
    Process.sleep(ms)
    retry()

  {:error, %Braintrust.Error{type: :authentication}} ->
    handle_auth_error()

  {:error, %Braintrust.Error{} = error} ->
    Logger.error("API error: #{error.message}")
    handle_error(error)
end
```

## Features

- **Projects** - Manage AI projects containing experiments, datasets, and logs
- **Experiments** - Run evaluations and compare results across runs
- **Datasets** - Version-controlled test data with support for pinning evaluations to specific versions
- **Logging/Tracing** - Production observability with span-based tracing
- **Prompts** - Version-controlled prompt management with caching
- **Functions** - Access to tools, scorers, and callable functions
- **Automatic Retry** - Exponential backoff for rate limits and transient errors
- **Pagination Streams** - Lazy iteration over paginated results

## API Coverage

| Resource | Endpoint | Status |
|----------|----------|--------|
| Projects | `/v1/project` | 🚧 Planned |
| Experiments | `/v1/experiment` | 🚧 Planned |
| Datasets | `/v1/dataset` | 🚧 Planned |
| Logs | `/v1/project_logs` | 🚧 Planned |
| Prompts | `/v1/prompt` | 🚧 Planned |
| Functions | `/v1/function` | 🚧 Planned |
| BTQL | `/btql` | 🚧 Planned |

## Resources

- [Braintrust Documentation](https://www.braintrust.dev/docs)
- [API Reference](https://www.braintrust.dev/docs/api-reference/introduction)
- [OpenAPI Specification](https://github.com/braintrustdata/braintrust-openapi)

## License

MIT
