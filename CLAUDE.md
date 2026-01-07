# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an Elixir Hex package providing an unofficial SDK for the [Braintrust.dev](https://braintrust.dev) AI evaluation and observability platform. There is no official Elixir SDK, making this package valuable for Elixir/Phoenix applications.

## Commands

```bash
# Install dependencies
mix deps.get

# Run all tests
mix test

# Run a single test file
mix test test/braintrust_test.exs

# Run a specific test by line number
mix test test/braintrust_test.exs:5

# Format code
mix format

# Check formatting without changes
mix format --check-formatted
```

## Architecture

### Module Structure

Following idiomatic Elixir patterns (inspired by Stripity Stripe, Req, ExAws), the package uses a flat namespace with structs colocated in their resource modules:

```
lib/braintrust/
├── braintrust.ex           # Main public API and entry point
├── client.ex               # HTTP client using Req library
├── config.ex               # Configuration management
├── error.ex                # %Braintrust.Error{type: atom(), ...}
├── pagination.ex           # Cursor-based pagination with Stream support
├── project.ex              # %Braintrust.Project{} + CRUD functions
├── experiment.ex           # %Braintrust.Experiment{} + functions
├── dataset.ex              # %Braintrust.Dataset{} + functions
├── log.ex                  # Logging/tracing (embeds Span struct)
├── prompt.ex               # %Braintrust.Prompt{} + functions
└── function.ex             # %Braintrust.Function{} + functions
```

**Design principles:**
- Each resource module defines its own struct (e.g., `%Braintrust.Project{}`)
- Structs are colocated with the functions that operate on them
- No separate `Types.*` or `Resources.*` namespaces (not idiomatic Elixir)
- Shared type specs can go in resource modules or a single `types.ex` if needed

### API Design Patterns

- All API functions return `{:ok, result}` or `{:error, %Braintrust.Error{}}` tuples
- Pagination should use Elixir Streams for lazy loading
- Implement retry logic with exponential backoff for 429, 5xx errors
- Use `@type` and `@spec` for all public functions
- **Use doctests** to provide usage examples in `@doc` blocks

### Doctests

Prefer doctests over separate test files when possible:

```elixir
@doc """
Gets a project by ID.

## Examples

    iex> {:ok, project} = Braintrust.Project.get("proj_123")
    iex> project.name
    "my-project"

"""
@spec get(binary()) :: {:ok, t()} | {:error, Braintrust.Error.t()}
def get(id), do: Client.get("/v1/project/#{id}")
```

- Doctests serve as both documentation AND tests
- Run with `mix test` (included automatically)
- Use separate test files for complex scenarios requiring mocking

### Braintrust API

- Base URL: `https://api.braintrust.dev/v1/`
- Auth: Bearer token via `Authorization: Bearer [api_key]`
- API key env var: `BRAINTRUST_API_KEY`
- Key prefixes: `sk-` (user keys), `bt-st-` (service tokens)

### Key Resources

| Resource | Endpoint | Purpose |
|----------|----------|---------|
| Projects | `/v1/project` | Container for experiments, datasets, logs |
| Experiments | `/v1/experiment` | Run evaluations, track results |
| Datasets | `/v1/dataset` | Test data for evaluations |
| Logs | `/v1/project_logs/{project_id}/insert` | Production traces |
| Prompts | `/v1/prompt` | Version-controlled prompts |
| Functions | `/v1/function` | Tools, scorers, callable functions |

### Research Reference

See `thoughts/shared/research/braintrust_hex_package.md` for comprehensive API documentation including:
- Complete endpoint specifications
- Data models and field definitions
- Pagination patterns
- Error handling strategies
- Rate limiting behavior
