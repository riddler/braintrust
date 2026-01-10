# Braintrust

An unofficial Elixir client for the [Braintrust](https://braintrust.dev) AI evaluation and observability platform.

Braintrust is an end-to-end platform for evaluating, monitoring, and improving AI applications. This Hex package provides Elixir/Phoenix applications with access to Braintrust's REST API for managing projects, experiments, datasets, logs, and prompts.

## Installation

Add `braintrust` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:braintrust, "~> 0.1"}
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

# Update a project
{:ok, project} = Braintrust.Project.update(project_id, %{name: "updated-name"})

# Delete a project (soft delete)
{:ok, project} = Braintrust.Project.delete(project_id)

# Stream through projects lazily (memory efficient)
Braintrust.Project.stream(limit: 50)
|> Stream.take(100)
|> Enum.to_list()
```

### Logging Traces

Log production traces for observability:

```elixir
# Log with raw maps
{:ok, _} = Braintrust.Log.insert(project_id, [
  %{
    input: %{messages: [%{role: "user", content: "Hello"}]},
    output: "Hi there!",
    scores: %{quality: 0.9},
    metadata: %{model: "gpt-4", environment: "production"},
    metrics: %{latency_ms: 250, input_tokens: 50, output_tokens: 25}
  }
])

# Or use Span structs for better type safety
spans = [
  %Braintrust.Span{
    input: %{messages: [%{role: "user", content: "Hello"}]},
    output: "Hi there!",
    scores: %{quality: 0.9},
    metadata: %{model: "gpt-4"},
    metrics: %{latency_ms: 250}
  }
]
{:ok, _} = Braintrust.Log.insert(project_id, spans)
```

### Experiments

Run evaluations and track results:

```elixir
# Create an experiment
{:ok, experiment} = Braintrust.Experiment.create(%{
  project_id: "proj_123",
  name: "gpt4-baseline"
})

# Insert evaluation events
{:ok, _} = Braintrust.Experiment.insert(experiment.id, [
  %{
    input: %{messages: [%{role: "user", content: "What is 2+2?"}]},
    output: "4",
    expected: "4",
    scores: %{accuracy: 1.0},
    metadata: %{model: "gpt-4"}
  }
])

# Get experiment summary
{:ok, summary} = Braintrust.Experiment.summarize(experiment.id)

# Stream through all events
Braintrust.Experiment.fetch_stream(experiment.id)
|> Stream.each(&process_event/1)
|> Stream.run()

# Add feedback to events
{:ok, _} = Braintrust.Experiment.feedback(experiment.id, [
  %{id: "event_123", scores: %{human_rating: 0.9}, comment: "Good response"}
])
```

### Datasets

Manage test data for evaluations:

```elixir
# Create a dataset
{:ok, dataset} = Braintrust.Dataset.create(%{
  project_id: "proj_123",
  name: "test-cases",
  description: "Q&A evaluation test cases"
})

# Insert test records
{:ok, _} = Braintrust.Dataset.insert(dataset.id, [
  %{input: %{question: "What is 2+2?"}, expected: "4"},
  %{input: %{question: "What is 3+3?"}, expected: "6", metadata: %{category: "math"}}
])

# Fetch dataset records
{:ok, result} = Braintrust.Dataset.fetch(dataset.id, limit: 100)

# Stream through all records
Braintrust.Dataset.fetch_stream(dataset.id)
|> Stream.each(&process_record/1)
|> Stream.run()

# Add feedback to records
{:ok, _} = Braintrust.Dataset.feedback(dataset.id, [
  %{id: "record_123", scores: %{quality: 0.95}, comment: "Excellent test case"}
])

# Get dataset summary
{:ok, summary} = Braintrust.Dataset.summarize(dataset.id)
```

### Prompts

Version-controlled prompt management with template variables:

```elixir
# Create a prompt
{:ok, prompt} = Braintrust.Prompt.create(%{
  project_id: "proj_123",
  name: "customer-support",
  slug: "customer-support-v1",
  model: "gpt-4",
  messages: [
    %{role: "system", content: "You are a helpful customer support agent."},
    %{role: "user", content: "{{user_input}}"}
  ]
})

# List prompts
{:ok, prompts} = Braintrust.Prompt.list(project_id: "proj_123")

# Get a prompt by ID
{:ok, prompt} = Braintrust.Prompt.get(prompt_id)

# Get a specific version
{:ok, prompt} = Braintrust.Prompt.get(prompt_id, version: "v2")

# Update a prompt (creates new version)
{:ok, prompt} = Braintrust.Prompt.update(prompt_id, %{
  messages: [
    %{role: "system", content: "Updated system prompt."},
    %{role: "user", content: "{{user_input}}"}
  ]
})

# Stream through prompts lazily
Braintrust.Prompt.stream(project_id: "proj_123")
|> Stream.take(50)
|> Enum.to_list()
```

### Functions

Manage tools, scorers, and callable functions:

```elixir
# List all functions
{:ok, functions} = Braintrust.Function.list()

# List scorers for a specific project
{:ok, scorers} = Braintrust.Function.list(
  project_id: "proj_123",
  function_type: "scorer"
)

# Create a code-based scorer
{:ok, scorer} = Braintrust.Function.create(%{
  project_id: "proj_123",
  name: "relevance-scorer",
  slug: "relevance-scorer-v1",
  function_type: "scorer",
  function_data: %{
    type: "code",
    data: %{
      runtime: "node",
      code: "export default async function({ input, output, expected }) {
        // Scoring logic here
        return { score: 0.9 };
      }"
    }
  }
})

# Get a function by ID
{:ok, func} = Braintrust.Function.get(function_id)

# Get a specific version
{:ok, func} = Braintrust.Function.get(function_id, version: "v2")

# Update a function
{:ok, func} = Braintrust.Function.update(function_id, %{
  description: "Updated relevance scorer with better accuracy"
})

# Stream through functions
Braintrust.Function.stream(function_type: "tool")
|> Stream.take(50)
|> Enum.to_list()
```

## LangChain Integration

If you're using [LangChain Elixir](https://github.com/brainlid/langchain), you can automatically log all LLM interactions to Braintrust:

```elixir
alias LangChain.Chains.LLMChain
alias LangChain.ChatModels.ChatOpenAI
alias LangChain.Message
alias Braintrust.LangChainCallbacks

{:ok, chain} =
  %{llm: ChatOpenAI.new!(%{model: "gpt-4"})}
  |> LLMChain.new!()
  |> LLMChain.add_callback(LangChainCallbacks.handler(
    project_id: "your-project-id",
    metadata: %{"environment" => "production"}
  ))
  |> LLMChain.add_message(Message.new_user!("Hello!"))
  |> LLMChain.run()
```

For streaming with time-to-first-token metrics:

```elixir
|> LLMChain.add_callback(LangChainCallbacks.streaming_handler(
  project_id: "your-project-id"
))
```

See `Braintrust.LangChainCallbacks` for full documentation.

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
- **Prompts** - Version-controlled prompt management with template variables and versioning
- **Functions** - Access to tools, scorers, and callable functions
- **Automatic Retry** - Exponential backoff for rate limits and transient errors
- **Pagination Streams** - Lazy iteration over paginated results

## API Coverage

| Resource | Endpoint | Status |
|----------|----------|--------|
| Projects | `/v1/project` | ✅ Implemented |
| Experiments | `/v1/experiment` | ✅ Implemented |
| Datasets | `/v1/dataset` | ✅ Implemented |
| Logs | `/v1/project_logs` | ✅ Implemented |
| Prompts | `/v1/prompt` | ✅ Implemented |
| Functions | `/v1/function` | ✅ Implemented |
| BTQL | `/btql` | 🚧 Planned |

## Resources

- [Braintrust Documentation](https://www.braintrust.dev/docs)
- [API Reference](https://www.braintrust.dev/docs/api-reference/introduction)
- [OpenAPI Specification](https://github.com/braintrustdata/braintrust-openapi)

## License

MIT
