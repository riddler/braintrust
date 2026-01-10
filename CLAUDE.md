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

<!-- usage-rules-start -->
<!-- usage-rules-header -->
# Usage Rules

**IMPORTANT**: Consult these usage rules early and often when working with the packages listed below.
Before attempting to use any of these packages or to discover if you should use them, review their
usage rules to understand the correct patterns, conventions, and best practices.
<!-- usage-rules-header-end -->

<!-- usage_rules-start -->
## usage_rules usage
_A dev tool for Elixir projects to gather LLM usage rules from dependencies_

## Using Usage Rules

Many packages have usage rules, which you should *thoroughly* consult before taking any
action. These usage rules contain guidelines and rules *directly from the package authors*.
They are your best source of knowledge for making decisions.

## Modules & functions in the current app and dependencies

When looking for docs for modules & functions that are dependencies of the current project,
or for Elixir itself, use `mix usage_rules.docs`

```
# Search a whole module
mix usage_rules.docs Enum

# Search a specific function
mix usage_rules.docs Enum.zip

# Search a specific function & arity
mix usage_rules.docs Enum.zip/1
```


## Searching Documentation

You should also consult the documentation of any tools you are using, early and often. The best 
way to accomplish this is to use the `usage_rules.search_docs` mix task. Once you have
found what you are looking for, use the links in the search results to get more detail. For example:

```
# Search docs for all packages in the current application, including Elixir
mix usage_rules.search_docs Enum.zip

# Search docs for specific packages
mix usage_rules.search_docs Req.get -p req

# Search docs for multi-word queries
mix usage_rules.search_docs "making requests" -p req

# Search only in titles (useful for finding specific functions/modules)
mix usage_rules.search_docs "Enum.zip" --query-by title
```


<!-- usage_rules-end -->
<!-- usage_rules:elixir-start -->
## usage_rules:elixir usage
# Elixir Core Usage Rules

## Pattern Matching
- Use pattern matching over conditional logic when possible
- Prefer to match on function heads instead of using `if`/`else` or `case` in function bodies
- `%{}` matches ANY map, not just empty maps. Use `map_size(map) == 0` guard to check for truly empty maps

## Error Handling
- Use `{:ok, result}` and `{:error, reason}` tuples for operations that can fail
- Avoid raising exceptions for control flow
- Use `with` for chaining operations that return `{:ok, _}` or `{:error, _}`

## Common Mistakes to Avoid
- Elixir has no `return` statement, nor early returns. The last expression in a block is always returned.
- Don't use `Enum` functions on large collections when `Stream` is more appropriate
- Avoid nested `case` statements - refactor to a single `case`, `with` or separate functions
- Don't use `String.to_atom/1` on user input (memory leak risk)
- Lists and enumerables cannot be indexed with brackets. Use pattern matching or `Enum` functions
- Prefer `Enum` functions like `Enum.reduce` over recursion
- When recursion is necessary, prefer to use pattern matching in function heads for base case detection
- Using the process dictionary is typically a sign of unidiomatic code
- Only use macros if explicitly requested
- There are many useful standard library functions, prefer to use them where possible

## Function Design
- Use guard clauses: `when is_binary(name) and byte_size(name) > 0`
- Prefer multiple function clauses over complex conditional logic
- Name functions descriptively: `calculate_total_price/2` not `calc/2`
- Predicate function names should not start with `is` and should end in a question mark.
- Names like `is_thing` should be reserved for guards

## Data Structures
- Use structs over maps when the shape is known: `defstruct [:name, :age]`
- Prefer keyword lists for options: `[timeout: 5000, retries: 3]`
- Use maps for dynamic key-value data
- Prefer to prepend to lists `[new | list]` not `list ++ [new]`

## Mix Tasks

- Use `mix help` to list available mix tasks
- Use `mix help task_name` to get docs for an individual task
- Read the docs and options fully before using tasks

## Testing
- Run tests in a specific file with `mix test test/my_test.exs` and a specific test with the line number `mix test path/to/test.exs:123`
- Limit the number of failed tests with `mix test --max-failures n`
- Use `@tag` to tag specific tests, and `mix test --only tag` to run only those tests
- Use `assert_raise` for testing expected exceptions: `assert_raise ArgumentError, fn -> invalid_function() end`
- Use `mix help test` to for full documentation on running tests

## Debugging

- Use `dbg/1` to print values while debugging. This will display the formatted value and other relevant information in the console.

<!-- usage_rules:elixir-end -->
<!-- usage_rules:otp-start -->
## usage_rules:otp usage
# OTP Usage Rules

## GenServer Best Practices
- Keep state simple and serializable
- Handle all expected messages explicitly
- Use `handle_continue/2` for post-init work
- Implement proper cleanup in `terminate/2` when necessary

## Process Communication
- Use `GenServer.call/3` for synchronous requests expecting replies
- Use `GenServer.cast/2` for fire-and-forget messages.
- When in doubt, use `call` over `cast`, to ensure back-pressure
- Set appropriate timeouts for `call/3` operations

## Fault Tolerance
- Set up processes such that they can handle crashing and being restarted by supervisors
- Use `:max_restarts` and `:max_seconds` to prevent restart loops

## Task and Async
- Use `Task.Supervisor` for better fault tolerance
- Handle task failures with `Task.yield/2` or `Task.shutdown/2`
- Set appropriate task timeouts
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure

<!-- usage_rules:otp-end -->
<!-- ex_quality-start -->
## ex_quality usage
_Run quality checks (credo, dialyzer, coverage, etc) in parallel with actionable output. Useful with LLMs._

# ExQuality - Usage Rules for LLM Assistants

## Overview

ExQuality is a parallel code quality checker for Elixir that runs format, compile, credo, dialyzer, dependency checks, and tests concurrently.

## First-time Setup

After adding `:ex_quality` to your dependencies:

```bash
# Interactive setup (recommended)
mix quality.init

# Use defaults without prompts
mix quality.init --skip-prompts

# Install all available tools
mix quality.init --all
```

This will:
- Detect which tools are already installed
- Prompt for which tools to add (credo, dialyzer, excoveralls recommended)
- Add dependencies to mix.exs with latest versions
- Run `mix deps.get` automatically
- Create tool configs (.credo.exs, coveralls.json, etc.)
- Create .quality.exs configuration file

**Available tools:**
- `credo` - Static code analysis
- `dialyzer` - Type checking (dialyxir)
- `coverage` - Test coverage (excoveralls)
- `doctor` - Documentation coverage
- `audit` - Security scanning (mix_audit)
- `gettext` - Internationalization

## Core Commands

### Quick mode (development)
```bash
mix quality --quick
```
- **Use during**: Active development, frequent changes, implementing features
- **Runs**: format, compile (dev+test), credo, dependencies, tests, doctor/gettext
- **Skips**: dialyzer (slow), coverage enforcement
- **Speed**: ~5 seconds typically

### Full mode (verification)
```bash
mix quality
```
- **Use before**: Commits, pull requests, CI/CD
- **Runs**: Everything including dialyzer and coverage enforcement

## CLI Flags

```bash
mix quality --quick               # Fast iteration mode
mix quality --skip-dialyzer       # Skip type checking
mix quality --skip-credo          # Skip static analysis
mix quality --skip-doctor         # Skip doc coverage
mix quality --skip-gettext        # Skip translation checks
mix quality --skip-dependencies   # Skip dependency checks
```

Flags can be combined: `mix quality --quick --skip-credo`

## Auto-Detection

ExQuality automatically enables stages based on installed dependencies:

- **Credo** - Auto-enabled if `:credo` installed
- **Dialyzer** - Auto-enabled if `:dialyxir` installed
- **Dependencies** - Always runs (unused deps check)
  - Security audit auto-enabled if `:mix_audit` installed
- **Doctor** - Auto-enabled if `:doctor` installed
- **Gettext** - Auto-enabled if `:gettext` installed
- **Coverage** - Uses `:excoveralls` if installed, else plain `mix test`

## Configuration

Create `.quality.exs` in project root:

```elixir
[
  # Disable specific stage
  dialyzer: [enabled: false],

  # Make credo less strict
  credo: [strict: false],

  # Configure dependencies
  dependencies: [
    check_unused: true,
    audit: false  # Skip security audit
  ]
]
```

## Working with ExQuality Output

### Success
```
✓ Format: No changes needed (0.1s)
✓ Compile: dev + test compiled (1.8s)
✓ Credo: No issues (1.2s)
✓ Dependencies: No unused dependencies (0.3s)
✓ Tests: 248 passed, 87.3% coverage (5.2s)

✅ All quality checks passed!
```

### Failures
When ExQuality fails, output includes **file:line references**:
- Parse file:line to locate issues
- Read affected files
- Explain what needs fixing
- Suggest/implement fixes
- Re-run `mix quality --quick`

Example failure:
```
✗ Credo: 5 issue(s) (0.4s)
────────────────────────────────────
lib/user.ex:42 - Module missing @moduledoc
lib/api.ex:58 - Function too complex
```

## Common Patterns

**After code changes:**
```
mix quality --quick  # Fast feedback
```

**Before committing:**
```
mix quality  # Full verification
```

**Dialyzer is slow:**
```elixir
# .quality.exs
[dialyzer: [enabled: false]]
```

**Coverage failing but tests pass:**
```bash
mix quality --quick  # Skips coverage enforcement
```

**Unused dependencies found:**
```bash
# ExQuality tells you which deps to remove
mix deps.unlock package_name
```

**Security vulnerabilities found:**
- Update affected packages to patched versions
- Follow recommendations in ExQuality output

<!-- ex_quality-end -->
<!-- usage-rules-end -->
