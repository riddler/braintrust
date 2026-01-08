# Braintrust Hex Package Research

**Date:** 2025-01-07
**Purpose:** Research for building an Elixir Hex package to integrate with Braintrust.dev AI evaluation platform
**Status:** Research Complete

---

## Table of Contents

1. [Overview](#overview)
2. [What is Braintrust?](#what-is-braintrust)
3. [Core Features](#core-features)
4. [API Authentication](#api-authentication)
5. [REST API Endpoints](#rest-api-endpoints)
6. [Data Models](#data-models)
7. [Request/Response Formats](#requestresponse-formats)
8. [Pagination](#pagination)
9. [Rate Limits](#rate-limits)
10. [Error Handling](#error-handling)
11. [Webhooks and Streaming](#webhooks-and-streaming)
12. [OpenTelemetry Integration](#opentelemetry-integration)
13. [Best Practices](#best-practices)
14. [Existing SDKs and Resources](#existing-sdks-and-resources)
15. [Alternatives Comparison](#alternatives-comparison)
16. [Pricing](#pricing)
17. [Suggested Hex Package Structure](#suggested-hex-package-structure)
18. [Elixir LangChain Integration](#elixir-langchain-integration)
19. [Sources](#sources)

---

## Overview

Braintrust is an end-to-end AI evaluation, observability, and development platform. There is **no official Elixir SDK**, making this Hex package valuable for Elixir/Phoenix applications that want to integrate with Braintrust.

The API is well-documented with an OpenAPI specification available, making client generation feasible.

---

## What is Braintrust?

Braintrust is a category-defining AI evaluation platform trusted by companies like Notion, Stripe, Vercel, Airtable, Instacart, Zapier, and Coda.

### Core Value Proposition

- Connects observability directly to systematic improvement
- Production traces become evaluation cases with one click
- Evaluation results appear on every pull request through CI/CD integration
- Customers report accuracy improvements of 30%+ within weeks
- Initial evaluations running in under an hour, basic integration within a day

### Key Differentiators

- Integrates evaluations, prompt management, and monitoring into single platform
- Unlike tools that treat evaluation as an afterthought
- Strong CI/CD integration with GitHub Actions
- Real-time collaborative debugging across teams

---

## Core Features

### Evaluation Framework

All evaluations consist of three components:
- **Data**: Test dataset (real production data or synthetic examples)
- **Task**: The AI function to test (any function with input → output)
- **Scores**: Scoring functions that measure quality (0-1 scale)

### Loop AI Agent

Intelligent agent that automates evaluation tasks:
- Analyzes prompts and generates better-performing versions
- Creates evaluation datasets tailored to use case
- Builds and refines scorers for specific quality metrics
- Available in Logs, Playgrounds, and Experiments

### Scoring Capabilities

| Type | Description | Examples |
|------|-------------|----------|
| Code-based metrics | Fast, cheap, deterministic | ExactMatch, LevenshteinDistance |
| LLM-as-a-judge | Handles nuanced, subjective criteria | Factuality, Relevance |
| Custom scorers | Write your own in a few lines | Application-specific |
| AutoEvals library | Pre-built scorers | Out-of-the-box quality metrics |

### Brainstore Database

Specialized database for AI application logs and traces:
- Query, filter, and analyze logs **80x faster** than traditional databases
- Handles complexity of modern AI workflows
- Traditional databases can't match this performance for AI workloads

### CI/CD Integration

- GitHub Actions integration for production-grade CI/CD
- Automatic evaluation runs on every pull request
- Detailed results posted as PR comments showing improvements/regressions
- Quality gates prevent regressions from reaching production

### AI Proxy

Single OpenAI-compatible API for multiple providers:
- Supports OpenAI, Anthropic, Google, and more
- Automatic tracing and caching
- Compare models side-by-side
- Switch providers without rewriting infrastructure

### Online Evaluation

Server-side evaluations run automatically and asynchronously:
- Pick from pre-built autoevals or custom scorers
- Define sampling rates and filters
- Evaluate production traffic at scale

---

## API Authentication

### Base URL

```
https://api.braintrust.dev/v1/
```

### Authentication Method

Bearer token authentication via header:

```
Authorization: Bearer [api_key]
```

### API Key Types

| Type | Prefix | Description |
|------|--------|-------------|
| User API keys | `sk-` | Created by users, inherit user's permissions |
| Service tokens | `bt-st-` | System integration with granular permissions, not tied to users |

### Key Management

- **Creation**: Organization settings at `https://www.braintrust.dev/app/settings?subroute=api-keys`
- **Security**: Keys are NOT stored server-side; displayed only once upon creation
- **Environment variable**: Convention is `BRAINTRUST_API_KEY`
- **Recovery**: Cannot recover lost keys; must create new ones
- **Rotation**: Rotate immediately if compromised

### All Endpoints Require Authentication

Except for explicitly public endpoints, all API calls require valid authentication.

---

## REST API Endpoints

### Projects (`/v1/project`)

Manage AI projects that contain experiments, datasets, and logs.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/v1/project` | List projects |
| POST | `/v1/project` | Create project |
| GET | `/v1/project/{project_id}` | Get project |
| DELETE | `/v1/project/{project_id}` | Delete project |
| PATCH | `/v1/project/{project_id}` | Partially update project |

**Query Parameters (List):**
- `limit` (integer, min: 0) - Number of objects to return
- `starting_after` (UUID) - Pagination cursor for next page
- `ending_before` (UUID) - Pagination cursor for previous page
- `ids` (UUID or array) - Filter by specific IDs
- `project_name` (string) - Search by name
- `org_name` (string) - Filter by organization

**Project Object Fields:**
```json
{
  "id": "uuid",
  "org_id": "uuid",
  "name": "string",
  "created": "datetime (optional)",
  "deleted_at": "datetime or null (optional)",
  "user_id": "uuid (optional)",
  "settings": {
    "comparison_key": "...",
    "baseline_experiment": "...",
    "field_ordering": "..."
  }
}
```

**Behavior Notes:**
- Creating a project with an existing name returns the existing project unmodified
- PATCH supports deep-merge for object-type fields

---

### Experiments (`/v1/experiment`)

Run evaluations and track experiment results.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/v1/experiment` | List experiments |
| POST | `/v1/experiment` | Create experiment |
| GET | `/v1/experiment/{experiment_id}` | Get experiment |
| DELETE | `/v1/experiment/{experiment_id}` | Delete experiment |
| PATCH | `/v1/experiment/{experiment_id}` | Partially update experiment |
| POST | `/v1/experiment/{experiment_id}/insert` | Insert experiment events |
| GET | `/v1/experiment/{experiment_id}/fetch` | Fetch experiment events (GET) |
| POST | `/v1/experiment/{experiment_id}/fetch` | Fetch experiment events (POST) |
| POST | `/v1/experiment/{experiment_id}/feedback` | Log feedback on events |
| GET | `/v1/experiment/{experiment_id}/summarize` | Summarize experiment |

**Insert Events Request:**
```json
{
  "events": [
    {
      "id": "unique-event-id",
      "input": {"question": "What is 2+2?"},
      "output": "4",
      "scores": {"accuracy": 0.9},
      "metadata": {"environment": "production"}
    }
  ]
}
```

**Feedback Request:**
```json
{
  "feedback": [
    {
      "id": "span-id",
      "scores": {"correctness": 0.8},
      "comment": "Needs improvement",
      "expected": "expected value",
      "metadata": {"user_id": "123"},
      "source": "app",
      "tags": ["user-feedback"]
    }
  ]
}
```

**Summarize Query Parameters:**
- `summarize_scores` (boolean) - Whether to include scores/metrics
- `comparison_experiment_id` (UUID) - Compare against specific experiment

**Summarize Response Structure:**
```json
{
  "project_name": "...",
  "experiment_name": "...",
  "project_url": "...",
  "experiment_url": "...",
  "comparison_experiment_name": "...",
  "scores": [
    {
      "name": "accuracy",
      "score": 0.85,
      "diff": 0.05,
      "improvements": 12,
      "regressions": 3
    }
  ],
  "metrics": [
    {
      "name": "latency",
      "metric": 250,
      "unit": "ms",
      "diff": -20,
      "improvements": 8,
      "regressions": 2
    }
  ]
}
```

---

### Datasets (`/v1/dataset`)

Manage test data for evaluations.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/v1/dataset` | List datasets |
| POST | `/v1/dataset` | Create dataset |
| GET | `/v1/dataset/{dataset_id}` | Get dataset |
| DELETE | `/v1/dataset/{dataset_id}` | Delete dataset |
| PATCH | `/v1/dataset/{dataset_id}` | Partially update dataset |
| POST | `/v1/dataset/{dataset_id}/insert` | Insert dataset events |
| GET | `/v1/dataset/{dataset_id}/fetch` | Fetch dataset events (GET) |
| POST | `/v1/dataset/{dataset_id}/fetch` | Fetch dataset events (POST) |
| POST | `/v1/dataset/{dataset_id}/feedback` | Log feedback on dataset events |
| GET | `/v1/dataset/{dataset_id}/summarize` | Summarize dataset |

**Dataset Record Structure:**
```json
{
  "input": {"question": "example question"},
  "expected": "expected output (optional)",
  "metadata": {"tag": "value"}
}
```

**Key Fields:**
- `input` - Set of inputs to recreate the example
- `expected` (optional) - Expected output (not necessarily ground truth)
- `metadata` (optional) - Key-value pairs for filtering/grouping

**Important Notes:**
- Every insert, update, and delete is versioned
- Can pin evaluations to specific dataset versions using `_xact_id`
- Integrated with evals, playground, and logging

---

### Logs/Traces (`/v1/project_logs`)

Submit production logs and traces for observability.

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/v1/project_logs/{project_id}/insert` | Insert log events |

**Trace/Span Hierarchy:**
- **Trace**: Roughly corresponds to a single request/interaction
- **Span**: Unit of work within a trace (e.g., single LLM call, tool invocation)

**Span Fields:**
```json
{
  "id": "uuid",
  "span_id": "unique-span-identifier",
  "root_span_id": "root-span-identifier",
  "span_parents": ["parent-span-id"],
  "input": {"messages": [{"role": "user", "content": "..."}]},
  "output": "response text",
  "expected": "expected output (optional)",
  "scores": {"accuracy": 0.9},
  "metadata": {"environment": "production", "model": "gpt-4"},
  "metrics": {"latency_ms": 250, "tokens": 150},
  "tags": ["production", "important"],
  "created": "2024-01-15T14:15:22Z",
  "error": "error message if applicable"
}
```

**Auto-Set Fields (Do NOT set manually):**
- `project_id`, `experiment_id`, `dataset_id`, `log_id`
- `span_id`, `root_span_id`, `span_parents` (let SDK manage)

**Trace Structure:**
- Directed acyclic graph (DAG) of spans
- Most executions form a tree
- Each span can have multiple parents
- UI supports single root span display

**Distributed Tracing:**
- Export span identifiers as opaque strings
- Resume traces in different processes
- Serialization format may change over time

---

### Prompts (`/v1/prompt`)

Version-controlled prompt management.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/v1/prompt` | List prompts |
| POST | `/v1/prompt` | Create prompt |
| GET | `/v1/prompt/{prompt_id}` | Get prompt |
| DELETE | `/v1/prompt/{prompt_id}` | Delete prompt |
| PATCH | `/v1/prompt/{prompt_id}` | Partially update prompt |

**Key Features:**
- Prompts are versioned, evaluated artifacts
- Version ID can be transaction ID or version identifier
- Can retrieve prompts at specific versions
- Client-side caching with disk persistence for reliability
- Integration with staged deployment and evaluation infrastructure

**Prompt Object Fields:**
```json
{
  "id": "uuid",
  "name": "prompt-name",
  "slug": "unique-identifier-for-retrieval",
  "description": "Prompt description",
  "model": "gpt-4",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user", "content": "{{user_input}}"}
  ]
}
```

---

### Functions (`/v1/function`)

Manage tools, scorers, and callable functions.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/v1/function` | List functions |
| POST | `/v1/function` | Create function |
| GET | `/v1/function/{function_id}` | Get function |
| DELETE | `/v1/function/{function_id}` | Delete function |
| PATCH | `/v1/function/{function_id}` | Partially update function |

**Function Types:**
1. **Tools** - General purpose code invoked by LLMs
2. **Scorers** - Functions for scoring LLM output quality (0-1 range)
3. **Prompts** - Versioned prompt templates (also accessible via `/v1/prompt`)

**Scorer Types:**
- Code-based (TypeScript/Python)
- LLM-as-a-judge
- Pre-built from autoevals library

**Key Features:**
- Functions can be composed together
- Support for streaming and structured outputs
- Sandboxed execution environment
- Can be synced between UI and codebase

---

### BTQL Query Endpoint (`/btql`)

SQL-like queries for complex data retrieval.

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/btql` | Execute BTQL query |

**Query Structure:**
```
select: * |
from: project_logs('<PROJECT_ID>') |
filter: tags includes 'triage' |
sort: created desc |
limit: 100 |
cursor: <pagination_cursor>
```

**Notes:**
- Used by all REST endpoints and UI internally
- Powerful for custom analytics and filtering

---

### AI Proxy (`/v1/proxy`)

Unified access to multiple LLM providers.

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/v1/proxy/completions` | Chat completions |
| POST | `/v1/proxy/embeddings` | Embeddings |
| WS | `/v1/realtime` | WebSocket for OpenAI Realtime API |

**Headers:**
- `x-bt-endpoint-name` - Specify endpoint by name
- `x-bt-use-cache` - Cache control (`auto`/`always`/`never`)

**Notes:**
- WebSocket endpoint uses `wss://braintrustproxy.com/v1` (NOT api.braintrust.dev)
- Automatic caching and observability
- OpenAI-compatible API format

---

### Additional Endpoints

| Resource | Endpoint | Description |
|----------|----------|-------------|
| Organizations | `/v1/organization` | Manage org settings and members |
| Users | `/v1/user` | Manage team members and roles |
| Roles | `/v1/role` | Role management |
| ACLs | `/v1/acl` | Access control lists |
| API Keys | `/v1/api_key` | List, create, delete API keys |
| Environment Variables | `/v1/env_var` | Secrets for functions (encrypted at rest) |
| Groups | `/v1/group` | Permission groups |
| Project Scores | `/v1/project_score` | Score configuration |
| Project Tags | `/v1/project_tag` | Tag management |
| Views | `/v1/view` | Custom query views |

---

## Data Models

### Common Fields Across Resources

**Identifiers:**
- `id` (UUID) - Primary identifier
- `org_id` (UUID) - Organization association
- `project_id` (UUID) - Project association

**Timestamps:**
- `created` (ISO 8601 datetime) - Creation time
- `deleted_at` (ISO 8601 datetime or null) - Soft deletion timestamp

**Versioning:**
- `_xact_id` - Transaction ID for versioning
- Used in datasets for version pinning

### Span Data Model (Complete)

```json
{
  "id": "uuid",
  "span_id": "unique-span-identifier",
  "root_span_id": "root-span-identifier",
  "span_parents": ["parent-span-id-1", "parent-span-id-2"],
  "input": {
    "messages": [
      {"role": "system", "content": "You are helpful."},
      {"role": "user", "content": "Hello!"}
    ]
  },
  "output": "Hi there! How can I help you today?",
  "expected": "A friendly greeting response",
  "scores": {
    "accuracy": 0.9,
    "relevance": 0.85,
    "helpfulness": 0.95
  },
  "metadata": {
    "environment": "production",
    "model": "gpt-4",
    "user_id": "user-123",
    "session_id": "session-456"
  },
  "metrics": {
    "latency_ms": 250,
    "input_tokens": 50,
    "output_tokens": 25,
    "total_tokens": 75
  },
  "tags": ["production", "chat", "important"],
  "created": "2024-01-15T14:15:22Z",
  "error": null
}
```

**Field Descriptions:**

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Unique identifier for the span |
| `span_id` | string | Span identifier for tracing |
| `root_span_id` | string | Root span of the trace |
| `span_parents` | array | Parent span IDs (supports DAG) |
| `input` | object | Input data (OpenAI message format recommended) |
| `output` | any | Output/response from the task |
| `expected` | any | Expected output for scoring (optional) |
| `scores` | object | Score values 0-1, keyed by score name |
| `metadata` | object | String keys, JSON-serializable values |
| `metrics` | object | Numbers not normalizable to [0,1], summed during aggregation |
| `tags` | array | String tags (only on top-level spans) |
| `created` | datetime | ISO 8601 timestamp |
| `error` | string/null | Error information if applicable |

### Scores Format

- Object with numeric values between 0 and 1
- Keys are score names, values are scores
- Example: `{"accuracy": 0.9, "relevance": 0.85}`

### Metrics Format

- Numbers that cannot be normalized to [0,1]
- Automatically summed during aggregation
- Example: `{"token_count": 150, "latency_ms": 250}`

---

## Request/Response Formats

### General Request Format

**Content-Type:** `application/json`

**Required Headers:**
```http
Authorization: Bearer [api_key]
Content-Type: application/json
```

### Success Response (2xx)

**List Response:**
```json
{
  "objects": [
    {"id": "uuid-1", "name": "..."},
    {"id": "uuid-2", "name": "..."}
  ],
  "starting_after": "uuid-for-next-page"
}
```

**Single Object Response:**
```json
{
  "id": "uuid",
  "name": "...",
  "created": "2024-01-15T14:15:22Z"
}
```

### Error Response (4xx/5xx)

```json
{
  "error": {
    "message": "Detailed error message describing what went wrong",
    "type": "error_type",
    "code": "error_code"
  }
}
```

---

## Pagination

### Cursor-Based Pagination

Braintrust uses cursor-based pagination (not offset-based).

**Parameters:**
- `limit` (integer) - Number of results per page
- `starting_after` (UUID) - Fetch next page after this ID
- `ending_before` (UUID) - Fetch previous page before this ID

**Constraint:** Can only use ONE cursor parameter at a time (`starting_after` OR `ending_before`).

### List Response with Pagination

```json
{
  "objects": [...],
  "starting_after": "next-page-cursor-uuid"
}
```

### Fetch Queries Pagination

- Only supports descending time order (latest to earliest `_xact_id`)
- Later pages may return earlier versions of rows from previous pages
- **Important:** Filter duplicates by `id` when combining results across pages
- Use explicit `cursor` from response (manual cursor construction is deprecated)

### SDK Auto-Pagination

Official SDKs provide iterators that handle pagination automatically. Elixir package should implement similar functionality.

---

## Rate Limits

### Rate Limiting Behavior

- Applied per organization and per endpoint
- Exceeding limits returns `429 Too Many Requests`
- Specific thresholds not publicly documented

### Automatic Retry

SDKs implement automatic retry with exponential backoff for:
- Connection errors
- 408 Request Timeout
- 409 Conflict
- 429 Too Many Requests
- 5xx Server Errors

**Default Retry Configuration:**
- 2 retries
- Short exponential backoff
- Configurable via SDK options

### Timeout

- Default: 1 minute per request
- Configurable in SDK clients

---

## Error Handling

### Error Types and HTTP Status Codes

| HTTP Status | Error Type | Description | Retry? |
|-------------|------------|-------------|--------|
| 400 | BadRequestError | Invalid request parameters | No |
| 401 | AuthenticationError | Missing or invalid API key | No |
| 403 | PermissionDeniedError | Insufficient permissions | No |
| 404 | NotFoundError | Resource not found | No |
| 408 | RequestTimeout | Request timeout | Yes |
| 409 | ConflictError | Conflict error | Yes |
| 422 | UnprocessableEntityError | Validation error | No |
| 429 | RateLimitError | Rate limit exceeded | Yes |
| >=500 | InternalServerError | Server error | Yes |
| N/A | APIConnectionError | Network connectivity problem | Yes |

### Error Response Structure

```json
{
  "error": {
    "message": "Detailed error message",
    "type": "error_type",
    "code": "error_code"
  }
}
```

### Recommended Retry Strategy

```
retry_count = 0
max_retries = 2
base_delay = 500ms

while retry_count < max_retries:
    response = make_request()
    if response.status in [408, 409, 429, 500..599] or connection_error:
        delay = base_delay * (2 ^ retry_count)
        sleep(delay + random_jitter)
        retry_count += 1
    else:
        return response
```

---

## Webhooks and Streaming

### Webhooks

**No native webhook support found.** The Braintrust platform does not appear to offer webhook notifications for events. The UI achieves real-time updates through polling.

### Streaming Support

**Functions Endpoint:**
- Supports streaming responses for AI completions

**AI Proxy WebSocket:**
- WebSocket endpoint: `wss://braintrustproxy.com/v1` (NOT api.braintrust.dev)
- `/realtime` endpoint for OpenAI Realtime API
- Full duplex communication for real-time AI interactions

---

## OpenTelemetry Integration

Braintrust natively supports OpenTelemetry via OTLP (OpenTelemetry Protocol), implementing the OpenTelemetry GenAI semantic conventions. This provides an alternative to the REST API for sending traces, particularly useful for real-time observability of LLM calls.

### OTEL Endpoint Configuration

**Base Endpoint:**
```
https://api.braintrust.dev/otel
```

**Signal-Specific Endpoint:**
```
https://api.braintrust.dev/otel/v1/traces
```

**Self-Hosted:** If self-hosting Braintrust, replace `https://api.braintrust.dev` with your custom API URL.

### Authentication Headers

```
Authorization: Bearer <Your API Key>
x-bt-parent: <prefix>:<value>
```

**Parent Header Prefixes:**

| Prefix | Description | Example |
|--------|-------------|---------|
| `project_id:` | Log to a project by ID | `project_id:abc123` |
| `project_name:` | Log to a project by name | `project_name:my-project` |
| `experiment_id:` | Log to an experiment by ID | `experiment_id:exp456` |

### GenAI Semantic Conventions

Braintrust automatically maps OTEL traces with GenAI attributes to its native format. The conventions follow the [OpenTelemetry GenAI specification](https://opentelemetry.io/docs/specs/semconv/gen-ai/).

**Span Naming Convention:** `{gen_ai.operation.name} {gen_ai.request.model}`

**Span Kind:** `CLIENT` (or `INTERNAL` for same-process models)

#### Required Span Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `gen_ai.operation.name` | string | Operation type: `chat`, `text_completion`, `embeddings` |
| `gen_ai.provider.name` | string | Provider: `openai`, `anthropic`, `azure`, `aws.bedrock`, etc. |

#### Recommended Span Attributes

| Attribute | Type | Description |
|-----------|------|-------------|
| `gen_ai.request.model` | string | Model name (e.g., `gpt-4`, `claude-3-opus`) |
| `gen_ai.usage.input_tokens` | int | Input token count |
| `gen_ai.usage.output_tokens` | int | Output token count |
| `gen_ai.response.finish_reasons` | array | Finish reasons: `["stop"]`, `["length"]`, `["tool_calls"]` |
| `gen_ai.response.id` | string | Unique response identifier |
| `gen_ai.request.temperature` | double | Temperature parameter |
| `gen_ai.request.max_tokens` | int | Max tokens parameter |
| `gen_ai.request.top_p` | double | Top-p parameter |
| `gen_ai.request.frequency_penalty` | double | Frequency penalty |
| `gen_ai.request.presence_penalty` | double | Presence penalty |
| `server.address` | string | GenAI server hostname |

#### Opt-In Attributes (Sensitive Data)

These should only be captured with explicit user consent:

| Attribute | Type | Description |
|-----------|------|-------------|
| `gen_ai.input.messages` | array | Chat history in structured format |
| `gen_ai.output.messages` | array | Model responses |
| `gen_ai.system_instructions` | string | System prompts |
| `gen_ai.tool.definitions` | array | Available tool specifications |

**Recording Format:** On events, these MUST be structured. On spans, they MAY be JSON strings.

### GenAI Events

#### Inference Details Event

**Name:** `event.gen_ai.client.inference.operation.details`

Captures details of a GenAI completion request including chat history and parameters.

#### Evaluation Event

**Name:** `event.gen_ai.evaluation.result`

Captures evaluation metrics for GenAI output quality.

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| `gen_ai.evaluation.name` | string | Yes | Metric name (e.g., "Relevance", "Accuracy") |
| `gen_ai.evaluation.score.value` | double | No | Numerical score |
| `gen_ai.evaluation.score.label` | string | No | Human-readable interpretation |
| `gen_ai.evaluation.explanation` | string | No | Justification for the score |

### Braintrust-Specific Attributes

Use the `braintrust.*` namespace to set Braintrust fields directly. These attributes are translated into Braintrust's native format.

### Elixir OTEL Configuration

**Dependencies (add to `mix.exs`):**
```elixir
def deps do
  [
    {:opentelemetry_exporter, "~> 1.8"},
    {:opentelemetry_api, "~> 1.2"},
    {:opentelemetry, "~> 1.3"}
  ]
end
```

**Note:** Add `opentelemetry_exporter` before other opentelemetry dependencies so it starts first.

**Configuration (`config/runtime.exs`):**
```elixir
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: "https://api.braintrust.dev/otel",
  otlp_headers: [
    {"authorization", "Bearer #{System.fetch_env!("BRAINTRUST_API_KEY")}"},
    {"x-bt-parent", "project_name:#{System.fetch_env!("BRAINTRUST_PROJECT_NAME")}"}
  ]
```

**Alternative: Environment Variables:**
```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=https://api.braintrust.dev/otel
export OTEL_EXPORTER_OTLP_HEADERS="authorization=Bearer sk-xxx, x-bt-parent=project_name:my-project"
```

**Protocol Options:**
- `:http_protobuf` (default, recommended)
- `:grpc`
- `:http_json`

### Elixir-Specific Considerations

1. **Application Startup:** OpenTelemetry SDK starts its supervision tree on boot; configure via application config or environment variables
2. **Release Configuration:** Set `opentelemetry` to `:temporary` so crashes don't terminate other applications:
   ```elixir
   def project do
     [
       releases: [
         my_app: [
           applications: [
             opentelemetry_exporter: :permanent,
             opentelemetry: :temporary
           ]
         ]
       ]
     ]
   end
   ```
3. **Context Propagation:** Use `otel_propagator_text_map:inject/1` and `extract/1` for distributed tracing
4. **Development:** Use stdout exporter for verification:
   ```elixir
   # config/dev.exs
   config :opentelemetry, traces_exporter: {:otel_exporter_stdout, []}
   ```

### REST API vs. OpenTelemetry

| Aspect | REST API | OpenTelemetry |
|--------|----------|---------------|
| **Best for** | CRUD operations, batch inserts | Real-time trace streaming |
| **Protocol** | HTTP/JSON | OTLP (protobuf/gRPC/HTTP) |
| **Span management** | Manual via SDK | Automatic via OTEL SDK |
| **Integration** | Braintrust-specific | Universal observability |
| **Elixir support** | Custom client | `opentelemetry_exporter` |

**Recommendation:** Use REST API for resource management (projects, experiments, datasets) and OpenTelemetry for real-time LLM observability.

---

## Best Practices

### Authentication

- Use environment variables for API keys (`BRAINTRUST_API_KEY`)
- Never commit API keys to source control
- Use service tokens for system integrations (not tied to user permissions)
- Rotate keys immediately if compromised
- Cannot recover lost keys; must create new ones

### Logging & Tracing

- Format input as OpenAI message list for UI "Try prompt" button support:
  ```json
  {"messages": [{"role": "user", "content": "..."}]}
  ```
- Put model and other parameters in metadata
- Let SDK manage span IDs, root span IDs, and span parents
- Only set top-level fields: input, output, expected, scores, metadata, metrics
- Tags only on top-level spans (traces), not subspans

### Batching

- SDK can buffer logs and send in batches for performance
- Reduces network requests and improves throughput
- Consider implementing batch insert in Elixir client

### Querying

- Use POST `/btql` endpoint for complex queries
- For fetch queries, prefer POST form over GET for complex parameters
- Filter duplicate rows by `id` when paginating fetch queries
- Select only needed columns to reduce response size
- Cast UUIDs to text for readability: `id::text`

### Datasets

- Use versioning to pin evaluations to specific dataset versions
- Track input, expected (optional), metadata structure consistently
- Integrate with evals and playground for full workflow

### Prompts

- Leverage client-side caching with disk persistence
- Use version IDs to retrieve specific versions
- Take advantage of staged deployment integration

### Error Handling

- Implement retry logic with exponential backoff
- Handle specific error types appropriately
- Monitor 429 rate limit errors and adjust request patterns
- Set appropriate timeouts for long-running operations

### Performance

- Use auto-pagination iterators instead of manual pagination
- Implement connection pooling in HTTP client
- Use BTQL for efficient data queries
- Consider Brainstore performance benefits for high-scale workloads

---

## Existing SDKs and Resources

### Official SDKs

| Language | Repository | Status |
|----------|------------|--------|
| Python | [braintrust-api-py](https://github.com/braintrustdata/braintrust-api-py) | Full-featured |
| TypeScript/JS | [braintrust-api-js](https://github.com/braintrustdata/braintrust-api-js) | Full-featured |
| Java | [braintrust-java](https://github.com/braintrustdata/braintrust-java) | Java 17+ |
| Go | [braintrust-sdk-go](https://github.com/braintrustdata/braintrust-sdk-go) | Beta |
| Ruby | [braintrust-ruby](https://github.com/braintrustdata/braintrust-ruby) | Available |
| Kotlin | Available via GitHub | Available |
| C# | Available via GitHub | Available |

**Note:** No official Elixir SDK exists.

### OpenAPI Specification

- **Repository:** https://github.com/braintrustdata/braintrust-openapi
- **Spec URL:** https://raw.githubusercontent.com/braintrustdata/braintrust-openapi/main/openapi/spec.json
- **Format:** OpenAPI 3.x specification
- **Scope:** ~49 paths, ~95 operations
- **Usage:** Can import into Postman, use for client code generation

### AutoEvals Library

- **Repository:** https://github.com/braintrustdata/autoevals
- Pre-built scorers for common evaluation tasks
- Available in Python and TypeScript

### Community Support

- **Discord:** https://discord.gg/6G8s47F44X
- **Email:** support@braintrust.dev
- **GitHub:** https://github.com/braintrustdata/braintrust-sdk

---

## Alternatives Comparison

### Top Competitors

| Platform | Best For | Pricing | Open Source | Self-Hosting |
|----------|----------|---------|-------------|--------------|
| **Braintrust** | Rapid experimentation, CI/CD | $249/mo Pro | No | Enterprise only |
| **Langfuse** | Open-source flexibility | $59/mo Pro | Yes | Yes (free) |
| **Arize Phoenix** | Full OSS control, agent tracing | Free unlimited | Yes | Yes (Docker) |
| **LangSmith** | LangChain ecosystem | $39/user/mo | No | No |
| **Maxim AI** | End-to-end lifecycle | Custom | No | No |
| **Galileo** | Complex agentic systems | Custom | No | No |

### Braintrust vs. Langfuse

**Braintrust strengths:**
- Strong in-UI experimentation
- Integrated playground
- Focus on evaluation/A/B testing

**Langfuse advantages:**
- Open-source transparency
- No proxy latency
- Full data control
- Built-in human annotation queues

**Key concern with Braintrust:** LLM proxy layer introduces potential latency, uptime, and data privacy risks.

### Braintrust vs. Arize Phoenix

**Phoenix advantages:**
- 100% free open source
- Single Docker container deployment
- 50+ instrumentations
- Framework-agnostic
- Unlimited evaluations
- No vendor lock-in

**Braintrust advantages:**
- More polished UI/UX
- Integrated AI proxy
- Stronger collaboration features

**Cost difference:** Phoenix is free forever; Braintrust minimum $249/month.

### When to Choose Braintrust

- Need rapid prototyping with excellent UI
- Want integrated playground and experimentation tools
- Prefer managed service over self-hosting
- CI/CD integration is critical
- Team collaboration features are important
- Budget allows for $249/month minimum

### When to Choose Alternatives

- **Langfuse:** Need open source, self-hosting, avoid proxy layer
- **Phoenix:** Want free unlimited usage, agent tracing, framework flexibility
- **LangSmith:** Already using LangChain/LangGraph extensively
- **Galileo:** Building complex agentic systems with cost-sensitive evaluations

---

## Pricing

### Free Tier - $0/month

**Best for:** Individual developers starting with AI evaluation

| Feature | Limit |
|---------|-------|
| Trace spans | 1 million |
| Processed data | 1 GB |
| Scores | 10,000 |
| Data retention | 14 days |
| Users | Unlimited |

### Pro Tier - $249/month

**Best for:** Small teams (up to 5 people) with growing workloads

| Feature | Included | Overage |
|---------|----------|---------|
| Trace spans | Unlimited | - |
| Processed data | 5 GB | $3/GB |
| Scores | 50,000 | $1.50/1,000 |
| Data retention | 1 month | $3/GB retained |
| Users | Unlimited | - |

### Enterprise Tier - Custom Pricing

**Best for:** Large organizations with high volumes or special requirements

- Premium support
- Self-hosting or hosted deployment options
- High-volume data processing
- Custom security requirements
- Dedicated support

### Additional Resources

- Pricing calculator available on braintrust.dev
- Flexible billing for usage beyond included limits

---

## Suggested Hex Package Structure

> **Note:** Updated to follow idiomatic Elixir patterns based on research of popular packages (Stripity Stripe, Req, ExAws, Tesla).

### Design Philosophy

Elixir conventions differ from OOP languages:
- **Structs are colocated** with the modules that operate on them
- **Flat namespaces** are preferred over deep hierarchies
- **No separate "types" folders** - this is not idiomatic Elixir
- **One module per file**, with file paths matching module namespaces

### Project Structure

```
braintrust/
├── lib/
│   ├── braintrust.ex              # Main API, public interface
│   └── braintrust/
│       ├── client.ex              # HTTP client (Req-based)
│       ├── config.ex              # Configuration management
│       ├── error.ex               # %Braintrust.Error{} struct + helpers
│       ├── pagination.ex          # Cursor pagination with Stream support
│       │
│       ├── project.ex             # %Braintrust.Project{} + CRUD functions
│       ├── experiment.ex          # %Braintrust.Experiment{} + functions
│       ├── dataset.ex             # %Braintrust.Dataset{} + functions
│       ├── log.ex                 # Logging API (Span/Trace structs embedded)
│       ├── prompt.ex              # %Braintrust.Prompt{} + functions
│       ├── function.ex            # %Braintrust.Function{} + functions
│       │
│       └── otel/                  # OpenTelemetry integration (optional)
│           ├── config.ex          # OTEL exporter configuration helpers
│           ├── genai.ex           # GenAI semantic convention helpers
│           └── span_builder.ex    # Convenience functions for creating GenAI spans
│
├── test/
│   ├── braintrust_test.exs
│   ├── support/
│   │   └── fixtures.ex            # Test fixtures
│   ├── project_test.exs
│   ├── experiment_test.exs
│   └── ...
├── mix.exs
├── README.md
└── LICENSE
```

### Struct Pattern (per module)

Each resource module defines its struct, type, and functions together:

```elixir
defmodule Braintrust.Project do
  @moduledoc """
  Manage Braintrust projects.
  """

  @type t :: %__MODULE__{
    id: binary(),
    name: binary(),
    org_id: binary(),
    created: DateTime.t() | nil,
    settings: map()
  }

  defstruct [:id, :name, :org_id, :created, settings: %{}]

  @spec list(keyword()) :: {:ok, [t()]} | {:error, Braintrust.Error.t()}
  def list(opts \\ []) do
    # Implementation
  end

  @spec get(binary()) :: {:ok, t()} | {:error, Braintrust.Error.t()}
  def get(id) do
    # Implementation
  end

  # ... create, update, delete
end
```

### Shared Types (if needed)

If types like `Span` or `Score` are used across multiple modules, define them as top-level modules:

```elixir
# lib/braintrust/span.ex
defmodule Braintrust.Span do
  @type t :: %__MODULE__{
    id: binary(),
    input: map(),
    output: term(),
    scores: %{optional(binary()) => float()},
    metadata: map()
  }

  defstruct [:id, :input, :output, scores: %{}, metadata: %{}]
end
```

**Do NOT create a `Braintrust.Types.*` namespace** - instead use `Braintrust.Span`, `Braintrust.Score`, etc.

### Suggested API Design

```elixir
# Configuration
config :braintrust, api_key: System.get_env("BRAINTRUST_API_KEY")

# Or runtime config
Braintrust.configure(api_key: "sk-xxx")

# Projects
{:ok, projects} = Braintrust.Project.list()
{:ok, project} = Braintrust.Project.create(%{name: "my-project"})
{:ok, project} = Braintrust.Project.get(project_id)
:ok = Braintrust.Project.delete(project_id)

# Logging traces
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

# Experiments
{:ok, experiment} = Braintrust.Experiment.create(project_id, %{name: "baseline-v1"})
{:ok, _} = Braintrust.Experiment.insert(experiment_id, events)
{:ok, summary} = Braintrust.Experiment.summarize(experiment_id)

# Datasets
{:ok, dataset} = Braintrust.Dataset.create(project_id, %{name: "test-cases"})
{:ok, _} = Braintrust.Dataset.insert(dataset_id, [
  %{input: %{question: "What is 2+2?"}, expected: "4"}
])

# Pagination as Stream
Braintrust.Project.list()
|> Braintrust.Pagination.stream()
|> Stream.take(100)
|> Enum.to_list()

# Error handling
case Braintrust.Project.get(invalid_id) do
  {:ok, project} ->
    handle_project(project)

  {:error, %Braintrust.Error{type: :not_found}} ->
    handle_not_found()

  {:error, %Braintrust.Error{type: :rate_limit, retry_after: ms}} ->
    Process.sleep(ms)
    retry()

  {:error, %Braintrust.Error{} = error} ->
    handle_error(error)
end
```

### OpenTelemetry Integration API

```elixir
# Dependencies for OTEL support (add to mix.exs)
{:opentelemetry_exporter, "~> 1.8"},
{:opentelemetry_api, "~> 1.2"},
{:opentelemetry, "~> 1.3"}

# Helper module for creating GenAI spans
defmodule Braintrust.OTEL.GenAI do
  @moduledoc """
  OpenTelemetry helpers for Braintrust GenAI tracing.

  Implements OpenTelemetry GenAI semantic conventions for automatic
  mapping to Braintrust's native format.
  """

  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Wraps an LLM call with proper GenAI span attributes.

  ## Options

  - `:operation` - Operation type (default: "chat")
  - `:temperature` - Temperature parameter
  - `:max_tokens` - Max tokens parameter
  - `:top_p` - Top-p parameter

  ## Example

      Braintrust.OTEL.GenAI.with_llm_span("gpt-4", :openai, fn ->
        OpenAI.chat_completion(messages)
      end)

      # With options
      Braintrust.OTEL.GenAI.with_llm_span("claude-3-opus", :anthropic,
        temperature: 0.7,
        max_tokens: 1000,
        fn -> Anthropic.messages(params) end
      )
  """
  @spec with_llm_span(String.t(), atom(), keyword(), (-> result)) :: result when result: term()
  def with_llm_span(model, provider, opts \\ [], fun) do
    span_name = "#{Keyword.get(opts, :operation, "chat")} #{model}"

    Tracer.with_span span_name, %{kind: :client} do
      Tracer.set_attributes([
        {"gen_ai.operation.name", Keyword.get(opts, :operation, "chat")},
        {"gen_ai.provider.name", to_string(provider)},
        {"gen_ai.request.model", model},
        {"gen_ai.request.temperature", Keyword.get(opts, :temperature)},
        {"gen_ai.request.max_tokens", Keyword.get(opts, :max_tokens)},
        {"gen_ai.request.top_p", Keyword.get(opts, :top_p)}
      ] |> reject_nil_values())

      result = fun.()

      # Set response attributes if result contains usage info
      set_usage_attributes(result)

      result
    end
  end

  @doc """
  Sets token usage attributes on the current span.

  ## Example

      Braintrust.OTEL.GenAI.set_usage(input_tokens: 50, output_tokens: 100)
  """
  @spec set_usage(keyword()) :: :ok
  def set_usage(opts) do
    Tracer.set_attributes([
      {"gen_ai.usage.input_tokens", Keyword.get(opts, :input_tokens)},
      {"gen_ai.usage.output_tokens", Keyword.get(opts, :output_tokens)}
    ] |> reject_nil_values())
  end

  @doc """
  Sets evaluation score on current span.

  ## Example

      Braintrust.OTEL.GenAI.set_evaluation("accuracy", 0.95,
        explanation: "Response matched expected output"
      )
  """
  @spec set_evaluation(String.t(), float(), keyword()) :: :ok
  def set_evaluation(name, score, opts \\ []) do
    Tracer.set_attributes([
      {"gen_ai.evaluation.name", name},
      {"gen_ai.evaluation.score.value", score},
      {"gen_ai.evaluation.score.label", Keyword.get(opts, :label)},
      {"gen_ai.evaluation.explanation", Keyword.get(opts, :explanation)}
    ] |> reject_nil_values())
  end

  @doc """
  Sets finish reasons on the current span.

  ## Example

      Braintrust.OTEL.GenAI.set_finish_reasons(["stop"])
  """
  @spec set_finish_reasons([String.t()]) :: :ok
  def set_finish_reasons(reasons) when is_list(reasons) do
    Tracer.set_attributes([
      {"gen_ai.response.finish_reasons", Jason.encode!(reasons)}
    ])
  end

  defp reject_nil_values(attrs) do
    Enum.reject(attrs, fn {_, v} -> is_nil(v) end)
  end

  defp set_usage_attributes(%{usage: usage}) when is_map(usage) do
    set_usage(
      input_tokens: Map.get(usage, :prompt_tokens) || Map.get(usage, :input_tokens),
      output_tokens: Map.get(usage, :completion_tokens) || Map.get(usage, :output_tokens)
    )
  end
  defp set_usage_attributes(_), do: :ok
end
```

### Key Implementation Considerations

1. **Use Req for HTTP** - Modern HTTP client with built-in retry support
2. **Implement retry logic** - Handle 429, 5xx with exponential backoff
3. **Pagination streams** - Elixir's Stream module is perfect for lazy pagination
4. **Colocate structs** - Define `@type t` and `defstruct` in same module as functions
5. **Comprehensive specs** - Add `@spec` to all public functions
6. **Config flexibility** - Support both compile-time and runtime configuration
7. **Single Error struct** - Use `%Braintrust.Error{type: atom()}` pattern, not separate error modules
8. **OTEL as optional feature** - Provide OpenTelemetry integration as opt-in module with optional deps
9. **GenAI semantic conventions** - Follow OTEL GenAI specs for interoperability with other observability tools
10. **Dual logging support** - Allow users to choose REST API or OpenTelemetry for tracing based on use case

---

## Elixir Convention Research

The structure above was updated based on research of idiomatic Elixir patterns:

### Key Findings

1. **No "types" folders** - Elixir colocates structs with the modules that operate on them
2. **Flat namespaces preferred** - `Braintrust.Project` not `Braintrust.Resources.Project`
3. **One module per file** - File paths match module namespaces
4. **Structs defined with their functions** - Following Stripity Stripe, Req, Tesla patterns

### Reference Packages Studied

| Package | Pattern | Notes |
|---------|---------|-------|
| [Stripity Stripe](https://github.com/beam-community/stripity-stripe) | `Stripe.Customer`, `Stripe.Charge` | Each resource is a top-level module with embedded struct |
| [Req](https://github.com/wojtekmach/req) | `Req.Request`, `Req.Response` | Structs in dedicated modules with their functions |
| [Tesla](https://github.com/elixir-tesla/tesla) | `Tesla.Env` | Single struct module for request/response data |
| [ExAws](https://github.com/ex-aws/ex_aws) | `ExAws.Operation.JSON` | Operation structs per protocol type |

### Sources for Elixir Conventions

- [Elixir Library Guidelines](https://hexdocs.pm/elixir/library-guidelines.html)
- [Elixir Naming Conventions](https://hexdocs.pm/elixir/naming-conventions.html)
- [Elixir Structs Documentation](https://hexdocs.pm/elixir/structs.html)
- [Elixir modules, files, directories, and naming conventions](https://ulisses.dev/elixir/2022/03/04/elixir-modules-files-directories-and-naming-conventions.html)

---

## Elixir LangChain Integration

The [Elixir LangChain](https://github.com/brainlid/langchain) library (v0.4.1, Dec 2025) provides a framework for integrating AI services into Elixir applications. Unlike the Python/JavaScript versions, Elixir LangChain embraces functional programming patterns. The Braintrust Hex package can integrate with LangChain via its callback system for seamless observability.

### LangChain Overview

**Package:** `{:langchain, "~> 0.4"}`

**Key Modules:**
- `LangChain.Chains.LLMChain` - Primary orchestration module
- `LangChain.ChatModels.*` - Provider integrations (OpenAI, Anthropic, Google, etc.)
- `LangChain.Function` - Tool/function calling bridge
- `LangChain.Message` / `LangChain.MessageDelta` - Message structures

**Supported Providers:** OpenAI, Anthropic Claude, xAI Grok, Google Gemini, Ollama, self-hosted Bumblebee models.

### ChainCallbacks System

LangChain provides a callback system via `LangChain.Chains.ChainCallbacks`. Callbacks are maps of event names to handler functions. All callback return values are discarded; use side effects for integration.

#### Available Callbacks

| Callback | Signature | Description |
|----------|-----------|-------------|
| `on_llm_new_delta` | `(LLMChain.t(), [MessageDelta.t()] -> any())` | Streaming tokens received |
| `on_llm_new_message` | `(LLMChain.t(), Message.t() -> any())` | Complete non-streamed message received |
| `on_llm_token_usage` | `(LLMChain.t(), TokenUsage.t() -> any())` | Token usage data reported |
| `on_llm_ratelimit_info` | `(LLMChain.t(), info :: map() -> any())` | Rate limiting info received |
| `on_llm_response_headers` | `(LLMChain.t(), headers :: map() -> any())` | HTTP response headers received |
| `on_message_processed` | `(LLMChain.t(), Message.t() -> any())` | LLMChain finished processing message |
| `on_message_processing_error` | `(LLMChain.t(), Message.t() -> any())` | Message processing failed |
| `on_error_message_created` | `(LLMChain.t(), Message.t() -> any())` | Chain generated automated error response |
| `on_tool_response_created` | `(LLMChain.t(), Message.t() -> any())` | Tool execution generated results |
| `on_retries_exceeded` | `(LLMChain.t() -> any())` | `max_retry_count` exhausted |

### Key Data Structures

#### TokenUsage

```elixir
%LangChain.TokenUsage{
  input: integer(),        # Input/prompt tokens
  output: integer(),       # Output/completion tokens
  raw: map(),              # LLM-specific usage data
  cumulative: [term()]     # Accumulated across multiple calls
}
```

**Helper functions:**
- `TokenUsage.total/1` - Returns sum of input + output
- `TokenUsage.add/2` - Combines two TokenUsage structs
- `TokenUsage.get/1` - Extracts usage from Message/MessageDelta metadata
- `TokenUsage.set/2` - Stores usage in message metadata

#### Message

```elixir
%LangChain.Message{
  role: :system | :user | :assistant | :tool,
  content: String.t() | [ContentPart.t()],
  tool_calls: [ToolCall.t()],
  tool_results: [ToolResult.t()],
  processed_content: term(),
  status: :complete | :cancelled | :length,
  metadata: map(),
  name: String.t(),
  index: integer()
}
```

#### MessageDelta (Streaming)

```elixir
%LangChain.MessageDelta{
  content: String.t() | ContentPart.t() | [],
  merged_content: [ContentPart.t()],
  role: :unknown | :assistant,
  metadata: map(),           # Contains token usage, model info
  tool_calls: [ToolCall.t()],
  status: :incomplete | :complete,
  index: integer()
}
```

Deltas arrive sequentially and are merged via `MessageDelta.merge_delta/2`. When `status: :complete`, convert to Message via `MessageDelta.to_message/1`.

#### LLMChain (Relevant Fields)

```elixir
%LLMChain{
  llm: ChatModel.t(),                 # Configured LLM
  messages: [Message.t()],            # All messages exchanged
  last_message: Message.t(),          # Most recent LLM message
  delta: MessageDelta.t(),            # Current merged delta state
  callbacks: [map()],                 # Registered callback handlers
  tools: [Function.t()],              # Available tools
  custom_context: map(),              # User-defined context
  current_failure_count: integer(),   # Retry tracking
  max_retry_count: integer(),         # Max retries allowed
  verbose: boolean()                  # Logging verbosity
}
```

### Braintrust Integration Strategy

The Braintrust Hex package can provide a pre-built callback handler that automatically logs LLM interactions to Braintrust.

#### Integration Architecture

```
┌─────────────────────┐     callbacks     ┌──────────────────────┐
│   LangChain         │──────────────────▶│  Braintrust          │
│   LLMChain          │                   │  CallbackHandler     │
└─────────────────────┘                   └──────────┬───────────┘
                                                     │
                                          ┌──────────▼───────────┐
                                          │  Braintrust.Log      │
                                          │  (REST API or OTEL)  │
                                          └──────────────────────┘
```

#### Callback Handler Implementation

```elixir
defmodule Braintrust.LangChain do
  @moduledoc """
  LangChain callback handler for Braintrust observability.

  Automatically logs LLM interactions to Braintrust when used with
  LangChain's LLMChain.

  ## Usage

      alias LangChain.Chains.LLMChain
      alias Braintrust.LangChain, as: BraintrustCallbacks

      chain =
        %{llm: ChatOpenAI.new!(%{model: "gpt-4"})}
        |> LLMChain.new!()
        |> LLMChain.add_callback(BraintrustCallbacks.handler(project_id: "proj_xxx"))
        |> LLMChain.add_messages([...])
        |> LLMChain.run()

  ## Options

  - `:project_id` - Braintrust project ID (required)
  - `:metadata` - Additional metadata to attach to all spans
  - `:tags` - Tags to attach to top-level spans
  - `:async` - Send logs asynchronously (default: true)
  - `:batch` - Batch multiple events before sending (default: true)
  """

  alias LangChain.Chains.LLMChain
  alias LangChain.{Message, MessageDelta, TokenUsage}

  @type handler_opts :: [
    project_id: String.t(),
    metadata: map(),
    tags: [String.t()],
    async: boolean(),
    batch: boolean()
  ]

  @doc """
  Creates a callback handler map for use with LLMChain.

  ## Example

      BraintrustCallbacks.handler(project_id: "proj_xxx")
      # => %{on_llm_new_message: fn..., on_llm_token_usage: fn..., ...}
  """
  @spec handler(handler_opts()) :: map()
  def handler(opts \\ []) do
    project_id = Keyword.fetch!(opts, :project_id)
    base_metadata = Keyword.get(opts, :metadata, %{})
    tags = Keyword.get(opts, :tags, [])

    # Store span context in process dictionary for correlation
    %{
      on_llm_new_message: fn chain, message ->
        log_message(project_id, chain, message, base_metadata, tags)
      end,

      on_llm_token_usage: fn chain, usage ->
        store_usage(usage)
      end,

      on_message_processed: fn chain, message ->
        log_processed_message(project_id, chain, message, base_metadata, tags)
      end,

      on_message_processing_error: fn chain, message ->
        log_error(project_id, chain, message, base_metadata, tags)
      end,

      on_tool_response_created: fn chain, message ->
        log_tool_execution(project_id, chain, message, base_metadata, tags)
      end,

      on_retries_exceeded: fn chain ->
        log_retries_exceeded(project_id, chain, base_metadata, tags)
      end
    }
  end

  @doc """
  Creates a streaming-aware callback handler that logs deltas.

  Use this when you need fine-grained streaming observability.
  """
  @spec streaming_handler(handler_opts()) :: map()
  def streaming_handler(opts \\ []) do
    base_handler = handler(opts)

    Map.merge(base_handler, %{
      on_llm_new_delta: fn chain, deltas ->
        # Track streaming progress, time-to-first-token, etc.
        track_streaming_deltas(chain, deltas)
      end
    })
  end

  # Private implementation functions

  defp log_message(project_id, chain, message, metadata, tags) do
    model = get_model_name(chain)

    Braintrust.Log.insert(project_id, %{
      events: [
        %{
          input: format_input(chain),
          output: format_output(message),
          scores: %{},
          metadata: Map.merge(metadata, %{
            "model" => model,
            "role" => to_string(message.role),
            "status" => to_string(message.status),
            "langchain_version" => langchain_version()
          }),
          metrics: build_metrics(message),
          tags: tags
        }
      ]
    })
  end

  defp log_processed_message(project_id, chain, message, metadata, tags) do
    usage = get_stored_usage()
    model = get_model_name(chain)

    Braintrust.Log.insert(project_id, %{
      events: [
        %{
          input: format_input(chain),
          output: format_output(message),
          scores: %{},
          metadata: Map.merge(metadata, %{
            "model" => model,
            "processed" => true,
            "tool_calls" => length(message.tool_calls || [])
          }),
          metrics: %{
            "input_tokens" => usage && usage.input,
            "output_tokens" => usage && usage.output,
            "total_tokens" => usage && TokenUsage.total(usage)
          } |> reject_nil_values(),
          tags: tags
        }
      ]
    })
  end

  defp log_error(project_id, chain, message, metadata, tags) do
    Braintrust.Log.insert(project_id, %{
      events: [
        %{
          input: format_input(chain),
          output: format_output(message),
          error: "Message processing error",
          metadata: Map.merge(metadata, %{
            "error" => true,
            "status" => to_string(message.status)
          }),
          tags: ["error" | tags]
        }
      ]
    })
  end

  defp log_tool_execution(project_id, chain, message, metadata, tags) do
    Braintrust.Log.insert(project_id, %{
      events: [
        %{
          input: %{"tool_results" => message.tool_results},
          output: format_output(message),
          metadata: Map.merge(metadata, %{
            "span_type" => "tool",
            "tool_count" => length(message.tool_results || [])
          }),
          tags: ["tool" | tags]
        }
      ]
    })
  end

  defp log_retries_exceeded(project_id, chain, metadata, tags) do
    Braintrust.Log.insert(project_id, %{
      events: [
        %{
          input: format_input(chain),
          output: nil,
          error: "Max retries exceeded",
          metadata: Map.merge(metadata, %{
            "max_retry_count" => chain.max_retry_count,
            "failure_count" => chain.current_failure_count
          }),
          tags: ["error", "retries_exceeded" | tags]
        }
      ]
    })
  end

  defp track_streaming_deltas(_chain, deltas) do
    # Track time-to-first-token, streaming metrics
    Enum.each(deltas, fn delta ->
      if is_nil(Process.get(:braintrust_first_token_time)) do
        Process.put(:braintrust_first_token_time, System.monotonic_time(:millisecond))
      end
      Process.put(:braintrust_last_delta, delta)
    end)
  end

  defp store_usage(usage) do
    Process.put(:braintrust_token_usage, usage)
  end

  defp get_stored_usage do
    Process.get(:braintrust_token_usage)
  end

  defp get_model_name(chain) do
    case chain.llm do
      %{model: model} -> model
      _ -> "unknown"
    end
  end

  defp format_input(chain) do
    %{
      "messages" => Enum.map(chain.messages, fn msg ->
        %{
          "role" => to_string(msg.role),
          "content" => format_content(msg.content)
        }
      end)
    }
  end

  defp format_output(message) do
    format_content(message.content)
  end

  defp format_content(content) when is_binary(content), do: content
  defp format_content(content) when is_list(content) do
    Enum.map(content, &format_content_part/1)
  end
  defp format_content(content), do: inspect(content)

  defp format_content_part(%{type: :text, content: text}), do: text
  defp format_content_part(%{type: type} = part), do: %{"type" => type, "data" => "[...]"}
  defp format_content_part(other), do: inspect(other)

  defp build_metrics(message) do
    case TokenUsage.get(message) do
      %TokenUsage{} = usage ->
        %{
          "input_tokens" => usage.input,
          "output_tokens" => usage.output,
          "total_tokens" => TokenUsage.total(usage)
        } |> reject_nil_values()
      _ ->
        %{}
    end
  end

  defp reject_nil_values(map) do
    Map.reject(map, fn {_, v} -> is_nil(v) end)
  end

  defp langchain_version do
    Application.spec(:langchain, :vsn) |> to_string()
  end
end
```

#### Usage Examples

**Basic Usage:**

```elixir
alias LangChain.Chains.LLMChain
alias LangChain.ChatModels.ChatOpenAI
alias LangChain.Message
alias Braintrust.LangChain, as: BraintrustCallbacks

# Create chain with Braintrust observability
{:ok, chain} =
  %{llm: ChatOpenAI.new!(%{model: "gpt-4", stream: false})}
  |> LLMChain.new!()
  |> LLMChain.add_callback(BraintrustCallbacks.handler(
    project_id: "proj_xxx",
    metadata: %{"environment" => "production"},
    tags: ["chat", "support"]
  ))
  |> LLMChain.add_message(Message.new_system!("You are a helpful assistant."))
  |> LLMChain.add_message(Message.new_user!("Hello!"))
  |> LLMChain.run()

# All LLM interactions automatically logged to Braintrust
```

**Streaming with Fine-Grained Tracking:**

```elixir
# Use streaming handler for time-to-first-token metrics
{:ok, chain} =
  %{llm: ChatOpenAI.new!(%{model: "gpt-4", stream: true})}
  |> LLMChain.new!()
  |> LLMChain.add_callback(BraintrustCallbacks.streaming_handler(
    project_id: "proj_xxx",
    tags: ["streaming"]
  ))
  |> LLMChain.add_messages([...])
  |> LLMChain.run()
```

**With Tool Calls:**

```elixir
alias LangChain.Function

# Define a tool
weather_tool = Function.new!(%{
  name: "get_weather",
  description: "Get current weather for a location",
  parameters_schema: %{
    type: "object",
    properties: %{
      location: %{type: "string", description: "City name"}
    },
    required: ["location"]
  },
  function: fn %{"location" => loc}, _context ->
    {:ok, "Sunny, 72°F in #{loc}"}
  end
})

{:ok, chain} =
  %{llm: ChatOpenAI.new!(%{model: "gpt-4"})}
  |> LLMChain.new!()
  |> LLMChain.add_tools([weather_tool])
  |> LLMChain.add_callback(BraintrustCallbacks.handler(project_id: "proj_xxx"))
  |> LLMChain.add_message(Message.new_user!("What's the weather in Tokyo?"))
  |> LLMChain.run(while_needs_response: true)

# Tool executions are logged as separate spans with tool metadata
```

**Phoenix LiveView Integration:**

```elixir
defmodule MyAppWeb.ChatLive do
  use MyAppWeb, :live_view

  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI
  alias Braintrust.LangChain, as: BraintrustCallbacks

  def handle_event("send_message", %{"message" => content}, socket) do
    live_view_pid = self()

    # Combine Braintrust logging with LiveView updates
    handlers = %{
      on_llm_new_delta: fn _chain, deltas ->
        Enum.each(deltas, fn delta ->
          send(live_view_pid, {:delta, delta})
        end)
      end,
      on_message_processed: fn _chain, message ->
        send(live_view_pid, {:complete, message})
      end
    }

    braintrust_handler = BraintrustCallbacks.streaming_handler(
      project_id: socket.assigns.project_id
    )

    Task.start(fn ->
      %{llm: ChatOpenAI.new!(%{model: "gpt-4", stream: true})}
      |> LLMChain.new!()
      |> LLMChain.add_callback(handlers)
      |> LLMChain.add_callback(braintrust_handler)
      |> LLMChain.add_messages(socket.assigns.messages)
      |> LLMChain.run()
    end)

    {:noreply, socket}
  end
end
```

### OpenTelemetry + LangChain + Braintrust

For comprehensive observability, combine LangChain callbacks with OpenTelemetry:

```elixir
defmodule Braintrust.LangChain.OTEL do
  @moduledoc """
  LangChain callbacks that emit OpenTelemetry spans.

  Use this when you want traces to flow through your existing
  OTEL infrastructure and into Braintrust via OTLP.
  """

  require OpenTelemetry.Tracer, as: Tracer

  def handler(opts \\ []) do
    %{
      on_llm_new_message: fn chain, message ->
        model = get_model_name(chain)
        span_name = "chat #{model}"

        Tracer.with_span span_name, %{kind: :client} do
          Tracer.set_attributes([
            {"gen_ai.operation.name", "chat"},
            {"gen_ai.provider.name", get_provider(chain)},
            {"gen_ai.request.model", model}
          ])

          # Usage will be set by on_llm_token_usage callback
        end
      end,

      on_llm_token_usage: fn _chain, usage ->
        Tracer.set_attributes([
          {"gen_ai.usage.input_tokens", usage.input},
          {"gen_ai.usage.output_tokens", usage.output}
        ])
      end,

      on_message_processing_error: fn chain, message ->
        Tracer.set_status(:error, "Message processing error")
        Tracer.set_attributes([
          {"error", true},
          {"error.message", inspect(message.content)}
        ])
      end
    }
  end

  defp get_model_name(chain) do
    case chain.llm do
      %{model: model} -> model
      _ -> "unknown"
    end
  end

  defp get_provider(chain) do
    chain.llm.__struct__
    |> Module.split()
    |> List.last()
    |> String.replace("Chat", "")
    |> String.downcase()
  end
end
```

### Design Considerations

1. **Callback Isolation:** LangChain discards callback return values. Use side effects (logging, message passing) only.

2. **Process Dictionary for Correlation:** Use `Process.put/2` to correlate data across callbacks (e.g., token usage from `on_llm_token_usage` with message from `on_message_processed`).

3. **Async Logging:** Default to async log submission to avoid blocking LLM response handling.

4. **Streaming Metrics:** The `on_llm_new_delta` callback enables time-to-first-token and streaming throughput metrics.

5. **Tool Span Hierarchy:** Log tool executions as child spans of the parent LLM call for proper trace visualization.

6. **Multiple Callbacks:** LangChain allows multiple callback handlers. Users can combine Braintrust callbacks with their own application-specific handlers.

### Suggested Module Structure Addition

```
lib/braintrust/
├── ...existing modules...
├── langchain.ex              # %Braintrust.LangChain - REST API callbacks
└── langchain/
    └── otel.ex               # %Braintrust.LangChain.OTEL - OTEL callbacks
```

### LangChain Sources

- [LangChain Elixir GitHub](https://github.com/brainlid/langchain)
- [LangChain Hex Package](https://hex.pm/packages/langchain)
- [ChainCallbacks Documentation](https://hexdocs.pm/langchain/LangChain.Chains.ChainCallbacks.html)
- [LLMChain Documentation](https://hexdocs.pm/langchain/LangChain.Chains.LLMChain.html)
- [TokenUsage Documentation](https://hexdocs.pm/langchain/LangChain.TokenUsage.html)
- [Message Documentation](https://hexdocs.pm/langchain/LangChain.Message.html)
- [MessageDelta Documentation](https://hexdocs.pm/langchain/LangChain.MessageDelta.html)
- [LangChain Demo Project](https://github.com/brainlid/langchain_demo)
- [Getting Started Guide](https://hexdocs.pm/langchain/getting_started.html)

---

## Sources

### Primary Documentation
- [API Reference Introduction](https://www.braintrust.dev/docs/api-reference/introduction)
- [Use the Data API](https://www.braintrust.dev/docs/deploy/api)
- [Authentication Documentation](https://www.braintrust.dev/docs/reference/platform/authentication)

### API Resources
- [Projects API](https://www.braintrust.dev/docs/reference/api/Projects)
- [Experiments API](https://www.braintrust.dev/docs/reference/api/Experiments)
- [Datasets API](https://www.braintrust.dev/docs/reference/api/Datasets)
- [Prompts API](https://www.braintrust.dev/docs/reference/api/Prompts)
- [Functions Guide](https://www.braintrust.dev/docs/guides/functions)
- [Scorers Documentation](https://www.braintrust.dev/docs/core/functions/scorers)
- [BTQL Documentation](https://www.braintrust.dev/docs/reference/btql)
- [AI Proxy Guide](https://www.braintrust.dev/docs/guides/proxy)
- [Proxy API Documentation](https://www.braintrust.dev/docs/reference/api/Proxy)
- [Env Vars Documentation](https://www.braintrust.dev/docs/reference/api/EnvVars)
- [Access Control Guide](https://www.braintrust.dev/docs/guides/access-control)
- [API Keys Documentation](https://www.braintrust.dev/docs/reference/api/ApiKeys)

### Logging and Tracing
- [Write Logs Guide](https://www.braintrust.dev/docs/guides/logs/write)
- [Customize Traces](https://www.braintrust.dev/docs/guides/traces/customize)
- [View Logs](https://www.braintrust.dev/docs/guides/logs/view)
- [Span Interface Documentation](https://www.braintrust.dev/docs/reference/libs/nodejs/interfaces/Span)

### Guides and Concepts
- [Datasets Guide](https://www.braintrust.dev/docs/guides/datasets)
- [Prompt Versioning Guide](https://www.braintrust.dev/docs/cookbook/recipes/PromptVersioning)
- [Monitor Logs and Experiments](https://www.braintrust.dev/docs/guides/monitor)
- [Evaluation quickstart](https://www.braintrust.dev/docs/evaluation)
- [How to eval: The Braintrust way](https://www.braintrust.dev/articles/how-to-eval)

### SDKs and OpenAPI
- [Braintrust OpenAPI Repository](https://github.com/braintrustdata/braintrust-openapi)
- [Python API Client](https://github.com/braintrustdata/braintrust-api-py)
- [JavaScript API Client](https://github.com/braintrustdata/braintrust-api-js)
- [AutoEvals Library](https://github.com/braintrustdata/autoevals)

### Comparisons and Alternatives
- [Best LLM evaluation platforms 2025](https://www.braintrust.dev/articles/best-llm-evaluation-platforms-2025)
- [Best AI evals tools for CI/CD in 2025](https://www.braintrust.dev/articles/best-ai-evals-tools-cicd-2025)
- [Braintrust Open Source Alternative - Phoenix](https://arize.com/docs/phoenix/resources/frequently-asked-questions/braintrust-open-source-alternative-llm-evaluation-platform-comparison)
- [Braintrust Alternatives - Langfuse](https://langfuse.com/faq/all/best-braintrustdata-alternatives)
- [Galileo vs Braintrust Comparison](https://galileo.ai/blog/galileo-vs-braintrust)

### Platform Information
- [Braintrust Home](https://www.braintrust.dev/home)
- [Pricing](https://www.braintrust.dev/pricing)
- [The three pillars of AI observability](https://www.braintrust.dev/blog/three-pillars-ai-observability)
- [Organizations Documentation](https://www.braintrust.dev/docs/reference/organizations)

### OpenTelemetry Integration
- [Braintrust OpenTelemetry Documentation](https://www.braintrust.dev/docs/integrations/sdk-integrations/opentelemetry)
- [Braintrust OTEL Logging Cookbook](https://www.braintrust.dev/docs/cookbook/recipes/OTEL-logging)
- [OpenTelemetry GenAI Semantic Conventions](https://opentelemetry.io/docs/specs/semconv/gen-ai/)
- [OpenTelemetry GenAI Client Spans](https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-spans/)
- [OpenTelemetry GenAI Events](https://opentelemetry.io/docs/specs/semconv/gen-ai/gen-ai-events/)
- [OpenTelemetry Erlang/Elixir Documentation](https://opentelemetry.io/docs/languages/erlang/)
- [opentelemetry_exporter Hex Documentation](https://hexdocs.pm/opentelemetry_exporter/)
- [Integrating OpenTelemetry with Elixir (Last9)](https://last9.io/blog/opentelemetry-with-elixir/)
