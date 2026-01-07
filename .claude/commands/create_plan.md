---
description: Create detailed implementation plans through interactive research and iteration
model: opus
---

# Implementation Plan

You are tasked with creating detailed implementation plans through an interactive, iterative process. You should be skeptical, thorough, and work collaboratively with the user to produce high-quality technical specifications.

## Initial Response

When this command is invoked:

1. **Check if parameters were provided**:
   - If a file path was provided (ticket, research doc, or other), skip the default message
   - Immediately read any provided files FULLY
   - Begin the research process
   - **Supported input files**:
     - Ticket files: `thoughts/shared/tickets/TICKET-123.md`
     - Research docs: `thoughts/shared/research/YYYY-MM-DD-topic.md`
     - GitHub issue references: `#123` or issue URLs

2. **If no parameters provided**, respond with:

```
I'll help you create a detailed implementation plan. Let me start by understanding what we're building.

Please provide:
1. The task description, ticket file, or research document
2. Any relevant context, constraints, or specific requirements
3. Links to related research or previous implementations

I'll analyze this information and work with you to create a comprehensive plan.

Examples:
- `/create_plan thoughts/shared/tickets/TICKET-123.md`
- `/create_plan thoughts/shared/research/2026-01-08-new-feature.md`
- `/create_plan #42` (GitHub issue number)
- `/create_plan think deeply about thoughts/shared/research/2026-01-08-new-feature.md`
```

Then wait for the user's input.

## Process Steps

### Step 1: Context Gathering & Initial Analysis

1. **Read all mentioned files immediately and FULLY**:
   - Ticket files (e.g., `thoughts/shared/tickets/TICKET-123.md`)
   - Research documents (e.g., `thoughts/shared/research/YYYY-MM-DD-topic.md`)
   - Related implementation plans
   - Any JSON/data files mentioned
   - **IMPORTANT**: Use the Read tool WITHOUT limit/offset parameters to read entire files
   - **CRITICAL**: DO NOT spawn sub-tasks before reading these files yourself in the main context
   - **NEVER** read files partially - if a file is mentioned, read it completely

   **When starting from a research doc**:
   - Research docs contain analysis, discoveries, and recommendations
   - Use them as the foundation for the plan - they've already done the investigation
   - Focus on structuring the implementation rather than re-researching
   - Validate that recommendations are still current if the doc is old

2. **Spawn initial research tasks to gather context**:
   If a research document was not provided with full file:line details, before asking the user any questions, use specialized agents to research in parallel:

   - Use the **codebase-locator** agent to find all files related to the ticket/task
   - Use the **codebase-analyzer** agent to understand how the current implementation works
   - If relevant, use the **thoughts-locator** agent to find any existing thoughts documents about this feature

   These agents will:
   - Find relevant source files, configs, and tests
   - Identify the specific directories to focus on
   - Trace data flow and key functions
   - Return detailed explanations with file:line references

3. **Read all files identified by research tasks or research document**:
   - After research tasks complete, read ALL files they identified as relevant
   - Read them FULLY into the main context
   - This ensures you have complete understanding before proceeding

4. **Analyze and verify understanding**:
   - Cross-reference the ticket requirements with actual code
   - Identify any discrepancies or misunderstandings
   - Note assumptions that need verification
   - Determine true scope based on codebase reality

5. **Present informed understanding and focused questions**:

   ```
   Based on the ticket and my research of the codebase, I understand we need to [accurate summary].

   I've found that:
   - [Current implementation detail with file:line reference]
   - [Relevant pattern or constraint discovered]
   - [Potential complexity or edge case identified]

   Questions that my research couldn't answer:
   - [Specific technical question that requires human judgment]
   - [Business logic clarification]
   - [Design preference that affects implementation]
   ```

   Only ask questions that you genuinely cannot answer through code investigation.

### Step 2: Research & Discovery

After getting initial clarifications:

1. **If the user corrects any misunderstanding**:
   - DO NOT just accept the correction
   - Spawn new research tasks to verify the correct information
   - Read the specific files/directories they mention
   - Only proceed once you've verified the facts yourself

2. **Create a research todo list** using TodoWrite to track exploration tasks

3. **Spawn parallel sub-tasks for comprehensive research**:
   - Create multiple Task agents to research different aspects concurrently
   - Use the right agent for each type of research:

   **For Elixir investigation:**
   - **elixir-inspector** - For runtime inspection using IEx

   **For deeper investigation:**
   - **codebase-locator** - To find more specific files (e.g., "find all files that handle [specific component]")
   - **codebase-analyzer** - To understand implementation details (e.g., "analyze how [system] works")
   - **codebase-pattern-finder** - To find similar features we can model after

   **For historical context:**
   - **thoughts-locator** - To find any research, plans, or decisions about this area
   - **thoughts-analyzer** - To extract key insights from the most relevant documents

   **For external resources:**
   - **web-search-researcher** - To find documentation or best practices

   Each agent knows how to:
   - Find the right files and code patterns
   - Identify conventions and patterns to follow
   - Look for integration points and dependencies
   - Return specific file:line references
   - Find tests and examples

3. **Wait for ALL sub-tasks to complete** before proceeding

4. **Present findings and design options**:

   ```
   Based on my research, here's what I found:

   **Current State:**
   - [Key discovery about existing code]
   - [Pattern or convention to follow]

   **Design Options:**
   1. [Option A] - [pros/cons]
   2. [Option B] - [pros/cons]

   **Open Questions:**
   - [Technical uncertainty]
   - [Design decision needed]

   Which approach aligns best with your vision?
   ```

### Step 3: Plan Structure Development

Once aligned on approach:

1. **Create initial plan outline**:

   ```
   Here's my proposed plan structure:

   ## Overview
   [1-2 sentence summary]

   ## Implementation Phases:
   1. [Phase name] - [what it accomplishes]
   2. [Phase name] - [what it accomplishes]
   3. [Phase name] - [what it accomplishes]

   Does this phasing make sense? Should I adjust the order or granularity?
   ```

2. **Get feedback on structure** before writing details

### Step 4: Detailed Plan Writing

After structure approval:

1. **Write the plan** to `thoughts/shared/plans/YYYY-MM-DD-GHXXX-description.md`
   - Format: `YYYY-MM-DD-GHXXX-description.md` where:
     - YYYY-MM-DD is today's date
     - GHXXX is the ticket number (omit if no ticket)
     - description is a brief kebab-case description
   - Examples:
     - With ticket: `2026-01-08-GH123-parent-child-tracking.md`
     - Without ticket: `2026-01-08-improve-error-handling.md`
2. **Use this template structure**:

````markdown
# [Feature/Task Name] Implementation Plan

## Overview

[Brief description of what we're implementing and why]

## Current State Analysis

[What exists now, what's missing, key constraints discovered]

## Desired End State

[A Specification of the desired end state after this plan is complete, and how to verify it]

### Key Discoveries:
- [Important finding with file:line reference]
- [Pattern to follow]
- [Constraint to work within]

## What We're NOT Doing

[Explicitly list out-of-scope items to prevent scope creep]

## Implementation Approach

[High-level strategy and reasoning]

## Phase 1: [Descriptive Name]

### Overview
[What this phase accomplishes]

### Changes Required:

#### 1. [Component/File Group]
**File**: `path/to/file.ext`
**Changes**: [Summary of changes]

```[language]
// Specific code to add/modify
```

### Success Criteria:

#### Automated Verification:
- [ ] Tests pass: `mix test`
- [ ] Code formatting passes: `mix format --check-formatted`

#### Manual Verification:
- [ ] Feature works as expected when tested in IEx
- [ ] API responses match expected format
- [ ] Error handling works correctly
- [ ] No regressions in related functions

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation from the human that the manual testing was successful before proceeding to the next phase.

---

## Phase 2: [Descriptive Name]

[Similar structure with both automated and manual success criteria...]

---

## Testing Strategy

### Unit Tests:
- [What to test]
- [Key edge cases]

### Integration Tests:
- [End-to-end scenarios]

### Manual Testing Steps:
1. [Specific step to verify feature]
2. [Another verification step]
3. [Edge case to test manually]

## Performance Considerations

[Any performance implications or optimizations needed]

## Migration Notes

[If applicable, how to handle existing data/systems]

## References

- Source document: `[ticket or research doc path]`
- Related research: `thoughts/shared/research/[relevant].md`
- Similar implementation: `[file:line]`
- GitHub issue: `#XXX` (if applicable)
````

### Step 5: Review

1. **Present the draft plan location**:

   ```
   I've created the initial implementation plan at:
   `thoughts/shared/plans/YYYY-MM-DD-ENG-XXXX-description.md`

   Please review it and let me know:
   - Are the phases properly scoped?
   - Are the success criteria specific enough?
   - Any technical details that need adjustment?
   - Missing edge cases or considerations?
   ```

2. **Iterate based on feedback** - be ready to:
   - Add missing phases
   - Adjust technical approach
   - Clarify success criteria (both automated and manual)
   - Add/remove scope items

3. **Continue refining** until the user is satisfied

## Important Guidelines

1. **Be Skeptical**:
   - Question vague requirements
   - Identify potential issues early
   - Ask "why" and "what about"
   - Don't assume - verify with code

2. **Be Interactive**:
   - Don't write the full plan in one shot
   - Get buy-in at each major step
   - Allow course corrections
   - Work collaboratively

3. **Be Thorough**:
   - Read all context files COMPLETELY before planning
   - Research actual code patterns using parallel sub-tasks
   - Include specific file paths and line numbers
   - Write measurable success criteria with clear automated vs manual distinction
   - Automated steps should use `mix` commands whenever possible - for example `mix verify` instead of running individual checks

4. **Be Practical**:
   - Focus on incremental, testable changes
   - Consider migration and rollback
   - Think about edge cases
   - Include "what we're NOT doing"

5. **Track Progress**:
   - Use TodoWrite to track planning tasks
   - Update todos as you complete research
   - Mark planning tasks complete when done

6. **No Open Questions in Final Plan**:
   - If you encounter open questions during planning, STOP
   - Research or ask for clarification immediately
   - Do NOT write the plan with unresolved questions
   - The implementation plan must be complete and actionable
   - Every decision must be made before finalizing the plan

## Success Criteria Guidelines

**Always separate success criteria into two categories:**

1. **Automated Verification** (can be run by execution agents):
   - Commands that can be run: `make test`, `npm run lint`, etc.
   - Specific files that should exist
   - Code compilation/type checking
   - Automated test suites

2. **Manual Verification** (requires human testing):
   - UI/UX functionality
   - Performance under real conditions
   - Edge cases that are hard to automate
   - User acceptance criteria

**Format example:**

```markdown
### Success Criteria:

#### Automated Verification:
- [ ] All checks pass: `mix verify`
- [ ] Tests pass: `MIX_ENV=test mix test`
- [ ] Database migrations apply: `mix ecto.migrate`

#### Manual Verification:
- [ ] New feature appears correctly in the UI
- [ ] Performance is acceptable with 1000+ items
- [ ] Error messages are user-friendly
- [ ] Feature works correctly on mobile devices
```

## Common Patterns

### For New API Resources

- Research existing resource patterns in the codebase first
- Create new resource module in `lib/braintrust/` (e.g., `lib/braintrust/project.ex`)
- Colocate struct definition with functions in the same module
- Implement CRUD functions following existing patterns
- Add doctests in `@doc` blocks for usage examples
- Add comprehensive tests in `test/` (e.g., `test/project_test.exs`)

### For New Features

- Research existing patterns in the codebase first
- Identify which modules need changes
- Follow existing conventions for function signatures
- Add doctests for new public functions
- Implement additional tests for complex logic

### For Refactoring

- Document current behavior
- Plan incremental changes
- Maintain backwards compatibility
- Ensure all tests pass

## Braintrust Library Code Patterns

### Module Structure

**Follow this pattern for resource modules:**

```elixir
defmodule Braintrust.Project do
  @moduledoc """
  Manage Braintrust projects.

  Projects are containers for experiments, datasets, and logs.
  """

  alias Braintrust.Client

  @type t :: %__MODULE__{
    id: binary(),
    name: binary(),
    org_id: binary()
  }

  defstruct [:id, :name, :org_id]

  @doc """
  Lists all projects.

  ## Options
    * `:limit` - Number of results per page
    * `:starting_after` - Cursor for pagination

  ## Examples

      iex> {:ok, projects} = Braintrust.Project.list(limit: 10)
      iex> is_list(projects)
      true

  """
  @spec list(keyword()) :: {:ok, [t()]} | {:error, Braintrust.Error.t()}
  def list(opts \\ []) do
    Client.get("/v1/project", opts)
  end

  @doc """
  Gets a project by ID.

  ## Examples

      iex> {:ok, project} = Braintrust.Project.get("proj_abc123")
      iex> project.name
      "my-project"

  """
  @spec get(String.t(), keyword()) :: {:ok, t()} | {:error, Braintrust.Error.t()}
  def get(project_id, opts \\ []) do
    Client.get("/v1/project/#{project_id}", opts)
  end
end
```

**Key points:**
- All functions return `{:ok, result}` or `{:error, %Braintrust.Error{}}`
- Include `@moduledoc`, `@doc`, and `@spec` for all public functions
- **Use doctests** to provide usage examples that also serve as tests
- Colocate struct definition (`@type t`, `defstruct`) with functions
- Delegate HTTP to the Client module

### Doctests

**Prefer doctests over separate test files when possible:**

- Doctests serve as both documentation AND tests
- They ensure examples in docs actually work
- Place examples in `@doc` blocks using `iex>` format
- Run with `mix test` (doctests are included automatically)

```elixir
@doc """
Creates a new span struct.

## Examples

    iex> span = Braintrust.Span.new(id: "span_123", input: %{query: "hello"})
    iex> span.id
    "span_123"

    iex> Braintrust.Span.new([])
    ** (KeyError) key :id not found

"""
def new(attrs) do
  struct!(__MODULE__, attrs)
end
```

### Error Handling

**Follow this pattern for error types:**

```elixir
defmodule Braintrust.Error do
  @type t :: %__MODULE__{
    type: atom(),
    message: String.t(),
    status: integer() | nil
  }

  defstruct [:type, :message, :status]
end
```

## Sub-task Spawning Best Practices

When spawning research sub-tasks:

1. **Spawn multiple tasks in parallel** for efficiency
2. **Each task should be focused** on a specific area
3. **Provide detailed instructions** including:
   - Exactly what to search for
   - Which directories to focus on
   - What information to extract
   - Expected output format
4. **Be EXTREMELY specific about directories**:
   - Include the full path context in your prompts to help agents locate the right files
5. **Specify read-only tools** to use
6. **Request specific file:line references** in responses
7. **Wait for all tasks to complete** before synthesizing
8. **Verify sub-task results**:
   - If a sub-task returns unexpected results, spawn follow-up tasks
   - Cross-check findings against the actual codebase
   - Don't accept results that seem incorrect

Example of spawning multiple tasks:

```python
# Spawn these tasks concurrently:
tasks = [
    Task("Research database schema", db_research_prompt),
    Task("Find API patterns", api_research_prompt),
    Task("Investigate UI components", ui_research_prompt),
    Task("Check test patterns", test_research_prompt)
]
```

## Example Interaction Flow

### From a ticket file:

```
User: /create_plan thoughts/shared/tickets/TICKET-123.md
Assistant: Let me read that ticket file completely first...

[Reads file fully]

Based on the ticket, I understand we need to track parent-child relationships for notes. Before I start planning, I have some questions...

[Interactive process continues...]
```

### From a research document:

```
User: /create_plan thoughts/shared/research/2026-01-08-authentication-options.md
Assistant: Let me read that research document completely first...

[Reads file fully]

Based on your research, I see you've already investigated three authentication approaches and recommended OAuth2.
The research includes file references and implementation notes. Let me structure this into an implementation plan...

[Proceeds with less initial research since the doc already contains findings]
```

### From a GitHub issue:

```
User: /create_plan #42
Assistant: Let me fetch the details for issue #42...

[Fetches issue via gh issue view 42 --json title,body,labels]

Based on the issue, I understand we need to [summary]. Let me research the codebase...

[Interactive process continues...]
```
