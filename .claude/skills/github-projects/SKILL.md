---
name: github-projects
description: Manage GitHub Projects v2 for Braintrust. Create backlog items, promote drafts to issues, list items, and update fields. Centralizes project configuration, CLI commands, and common pitfalls.
---

# GitHub Projects Skill

Manage GitHub Projects v2 using the `gh` CLI and GraphQL API. This skill handles creating items, promoting drafts to issues, and managing project fields.

## Operations

Determine which operation is needed based on the request:

### Create Backlog Item

**Trigger**: User wants to add a new item to the backlog

1. Analyze the request to determine:
   - Title (short, action-oriented)
   - Description (brief context)
   - Category: Feature | Bug | Improvement | Technical debt | Documentation | Research
   - Size: XS | S | M | L | XL
   - Priority: P0 | P1 | P2

2. Create the draft item:
   ```bash
   .claude/skills/github-projects/scripts/create-draft-item.sh "Title" "Body"
   ```

3. Extract the `id` (PVTI_xxx) from the JSON response

4. Set all fields:
   ```bash
   .claude/skills/github-projects/scripts/set-item-status.sh PVTI_xxx "Backlog"
   .claude/skills/github-projects/scripts/set-item-category.sh PVTI_xxx "Feature"
   .claude/skills/github-projects/scripts/set-item-size.sh PVTI_xxx "M"
   .claude/skills/github-projects/scripts/set-item-priority.sh PVTI_xxx "P1"
   ```

5. Confirm creation with summary

### Create Issue (Direct)

**Trigger**: User wants to create a GitHub issue directly (not from backlog)

This is for creating issues that don't need to go through the backlog workflow first.

1. **Analyze user input** to extract:
   - Main problem or feature request
   - Technical components involved
   - Priority indicators (urgent, blocking, nice-to-have, etc.)
   - Affected areas of codebase

2. **Determine appropriate labels**:
   - One **category label** (see Category Labels below)
   - Zero or more **area labels** (see Area Labels Reference below)

3. **Structure the issue**:

   **Title**: Clear and concise (50-80 characters), start with action verb when appropriate

   **Body format for features/enhancements**:
   ```markdown
   ## Description
   [Clear explanation of the issue/feature]

   ## Context
   [Why this is needed, background information]

   ## Proposed Solution
   [High-level approach or ideas]

   ## Acceptance Criteria
   - [ ] [Specific, measurable outcome]
   - [ ] [Another criterion]

   ## Technical Notes
   - Affected files/components: [list]
   - Dependencies: [any related issues or requirements]
   - Considerations: [edge cases, constraints, etc.]
   ```

   **Body format for bugs**:
   ```markdown
   ## Bug Description
   [What's wrong and how it manifests]

   ## Steps to Reproduce
   1. [First step]
   2. [Second step]
   3. [See error]

   ## Expected Behavior
   [What should happen]

   ## Actual Behavior
   [What actually happens]

   ## Technical Context
   - Affected files: [list]
   - Error messages: [if any]
   - Related issues: [if any]

   ## Possible Solution
   [If you have ideas on how to fix it]
   ```

4. **Present draft to user** before creating:
   - Show proposed title, labels, and body
   - Offer options: create as-is, make adjustments, add/remove labels, change title

5. **Create the issue** after user approval:
   ```bash
   gh issue create \
     --title "Issue title here" \
     --body "$(cat <<'EOF'
   Issue body here
   EOF
   )" \
     --label "category-label" \
     --label "area-label1" \
     --label "area-label2"
   ```

6. **Confirm creation** with:
   - Issue number and URL
   - Next steps: `/research_codebase #XXX`, `/create_plan #XXX`

---

### Promote Item to Issue

**Trigger**: User wants to convert a draft item to a real GitHub issue

1. List backlog items:
   ```bash
   .claude/skills/github-projects/scripts/list-backlog-items.sh
   ```

2. Filter for `status: "Backlog"` AND `content.type: "DraftIssue"`

3. Present options to user via AskUserQuestion

4. Show selected item details and ask if they want to expand description

5. If expanding, update using DI_ ID with BOTH title and body:
   ```bash
   .claude/skills/github-projects/scripts/update-draft-content.sh DI_xxx "Title" "Body"
   ```

6. Convert via GraphQL mutation using PVTI_ ID:
   ```bash
   .claude/skills/github-projects/scripts/promote-to-issue.sh PVTI_xxx
   ```

7. **Add labels** - Apply both category and area labels:

   a. **Category label** (always add one based on Category field):
      ```bash
      .claude/skills/github-projects/scripts/add-issue-labels.sh <issue-number> <category-label>
      ```

   b. **Area labels** (add zero or more based on issue content analysis):
      - Analyze the issue title and description
      - Determine which system areas are affected (see Area Labels Reference below)
      - Add all applicable area labels:
      ```bash
      .claude/skills/github-projects/scripts/add-issue-labels.sh <issue-number> <label1> <label2> ...
      ```

   c. Only add labels you're confident about - other commands (`/research_codebase`, `/create_plan`) can add more later

8. Confirm with issue URL, applied labels, and next steps

### List Backlog Items

**Trigger**: User wants to see current backlog

1. Fetch items:
   ```bash
   .claude/skills/github-projects/scripts/list-backlog-items.sh
   ```

2. Filter and format for display
3. Show: Title, Category, Size, Priority, Status

### Update Item Fields

**Trigger**: User wants to change an item's category, size, priority, or status

1. Identify the item (by title search or ID)
2. Use the appropriate field script
3. Confirm the change

---

## Project Configuration

| Setting | Value |
|---------|-------|
| Project Number | 3 |
| Owner | riddler |
| Project ID | PVT_kwDOArMuY84BMFuv |
| Repository ID | R_kgDOQ1YEZQ |
| Project URL | https://github.com/orgs/riddler/projects/3 |

---

## ID Types Reference

Understanding the different ID prefixes is critical:

| Prefix | Type | Used For |
|--------|------|----------|
| `PVT_` | Project ID | Identifying the project itself |
| `PVTI_` | Project Item ID | Referencing items in the project (for GraphQL mutations, field edits) |
| `DI_` | Draft Issue ID | Editing draft issue content (title, body) |
| `R_` | Repository ID | Converting drafts to real issues |
| `PVTSSF_` | Field ID | Setting custom field values |
| `I_` | Issue ID | Real GitHub issues (after conversion) |

---

## Available Scripts

All scripts are in `.claude/skills/github-projects/scripts/`:

### List All Project Items

```bash
.claude/skills/github-projects/scripts/list-backlog-items.sh [limit]
```

Returns JSON with all project items. Default limit: 50.

### Create New Draft Item

```bash
.claude/skills/github-projects/scripts/create-draft-item.sh "Title" "Body"
```

Returns JSON with the new item including its `id` (PVTI_xxx).

### Set Item Fields

```bash
# Set Status
.claude/skills/github-projects/scripts/set-item-status.sh PVTI_xxx "Backlog|Ready|In progress|In review|Done"

# Set Priority
.claude/skills/github-projects/scripts/set-item-priority.sh PVTI_xxx "P0|P1|P2"

# Set Size
.claude/skills/github-projects/scripts/set-item-size.sh PVTI_xxx "XS|S|M|L|XL"

# Set Category
.claude/skills/github-projects/scripts/set-item-category.sh PVTI_xxx "Feature|Bug|Improvement|Technical debt|Documentation|Research"
```

### Edit Draft Issue Content

**CRITICAL**: Use Draft Issue ID (DI_xxx), and MUST include both title and body!

```bash
.claude/skills/github-projects/scripts/update-draft-content.sh DI_xxx "Title" "Body"
```

### Convert Draft to Issue

```bash
.claude/skills/github-projects/scripts/promote-to-issue.sh PVTI_xxx
```

Returns JSON with the new issue number and URL.

### Add Labels to Issue

```bash
.claude/skills/github-projects/scripts/add-issue-labels.sh <issue-number> <label1> [label2] [label3]
```

---

## Field IDs and Options

### Status (Field ID: PVTSSF_lADOArMuY84BMFuvzg7eNWc)

| Value | Option ID |
|-------|-----------|
| Backlog | `f75ad846` (default for new items) |
| Ready | `e18bf179` |
| In progress | `47fc9ee4` |
| In review | `aba860b9` |
| Done | `98236657` |

### Priority (Field ID: PVTSSF_lADOArMuY84BMFuvzg7eNbc)

| Value | Option ID | Description |
|-------|-----------|-------------|
| P0 | `79628723` | Critical/Urgent |
| P1 | `0a877460` | High priority |
| P2 | `da944a9c` | Normal priority |

### Size (Field ID: PVTSSF_lADOArMuY84BMFuvzg7eNbg)

| Value | Option ID | Description |
|-------|-----------|-------------|
| XS | `911790be` | Trivial, < 1 hour |
| S | `b277fb01` | Small, few hours |
| M | `86db8eb3` | Medium, a day or two |
| L | `853c8207` | Large, several days |
| XL | `2d0801e2` | Very large, a week+ |

### Category (Field ID: PVTSSF_lADOArMuY84BMFuvzg7eft0)

| Value | Option ID | Description |
|-------|-----------|-------------|
| Feature | `d060bbcf` | New functionality |
| Bug | `4d270e92` | Something broken |
| Improvement | `a9b1f704` | Enhancement to existing |
| Technical debt | `61bd9539` | Cleanup, refactoring, perf |
| Documentation | `cef3f397` | Docs, comments, guides |
| Research | `5777c73d` | Investigation, spikes |

---

## Label Organization

### Category Labels (mutually exclusive - choose one)

These map 1:1 with project Category field values. Use this table when adding the category label during promotion:

| Category | GitHub Label | Description |
|----------|-------------|-------------|
| Feature | `feature` | New functionality |
| Bug | `bug` | Something broken |
| Improvement | `improvement` | Enhancement to existing functionality |
| Technical debt | `refactor` | Cleanup, refactoring, performance |
| Documentation | `documentation` | Docs, comments, guides |
| Research | `research` | Investigation, spikes |

### Area Labels Reference (additive - choose zero or more)

These indicate which part of the system is affected. Add all that apply based on the issue content.

| Label | When to Apply |
|-------|---------------|
| `client` | Changes to HTTP client, request handling, retries, or authentication |
| `resources` | Changes to API resource modules (Project, Experiment, Dataset, etc.) |
| `pagination` | Changes to pagination, cursors, or streaming functionality |
| `errors` | Error handling, error types, or error responses |
| `types` | Type definitions, structs, or typespecs |
| `testing` | Test files, test infrastructure, test helpers, or testing patterns |
| `documentation` | Documentation, README, guides, or examples |
| `ci/cd` | GitHub Actions, build pipelines, or automated checks |
| `config` | Configuration handling, environment variables, or settings |

**Detection Tips:**
- Look for keywords in title/description: "HTTP", "request" → `client`
- Look for file paths mentioned: `lib/braintrust/resources/` → `resources`
- Look for feature areas: "list", "pagination", "cursor" → `pagination`
- Look for error terms: "error", "exception", "failure" → `errors`
- When in doubt, don't add the label - it can be added later by `/research_codebase` or `/create_plan`

---

## Common Pitfalls

### 1. Wrong ID for Draft Editing

**Problem**: Using `PVTI_` ID when editing draft title/body fails.

**Solution**: Use the `DI_` ID (found in `content.id` of the item response).

```bash
# From item-list response:
# "id": "PVTI_lAHNEADOASyVK84Iurnx"           <- Project Item ID
# "content": { "id": "DI_lAHNEADOASyVK84CgTLs" } <- Draft Issue ID

# Use DI_ for title/body edits
```

### 2. Missing Title When Updating Body

**Problem**: Updating body fails with "Title can't be blank".

**Solution**: Always include `--title` when updating body, even if unchanged.

### 3. Using PVTI_ for Field Edits vs Content Edits

**Rule of thumb**:
- **PVTI_** for setting project fields (status, priority, size, category)
- **DI_** for editing draft content (title, body)

### 4. Items Already Converted

**Problem**: Attempting to promote an item that's already a real Issue.

**Detection**: Check `content.type` - if it's "Issue" (not "DraftIssue"), it's already converted.

**Solution**: Skip and inform user, or just add labels to existing issue.

### 5. GraphQL Mutation Item ID

**Rule**: The `convertProjectV2DraftIssueItemToIssue` mutation uses the Project Item ID (`PVTI_`), NOT the Draft Issue ID.

---

## Error Recovery

### "Title can't be blank"
Add `--title` parameter with the existing title.

### "ID must be the ID of the draft issue content which is prefixed with `DI_`"
You used PVTI_ when you needed DI_. Get the DI_ ID from `content.id` in the item response.

### GraphQL mutation fails
- Verify the item is a DraftIssue (not already an Issue)
- Check the PVTI_ ID is correct
- Ensure Repository ID is R_kgDOQ1YEZQ

### Label addition fails
Non-fatal - note it to user, they can add manually via GitHub UI.
