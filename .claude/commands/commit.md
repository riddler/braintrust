---
description: Analyze changes and create a well-crafted commit
model: sonnet
---

# Commit Changes

This command handles the workflow for committing changes on a branch.

## Process:

### Step 0: Pre-commit Checks

1. Run `mix test` to ensure tests pass
2. Run `mix format --check-formatted` to ensure code is formatted
3. Fix ALL issues before proceeding

### Step 1: Analyze Changes

1. Run `git status` to see all modified/added files
2. Run `git diff main...HEAD --stat` to see scope of changes
3. Run `git log main...HEAD --oneline` to see any local commits
4. Analyze the changes to understand:
   - What features were added
   - What bugs were fixed
   - What was refactored or improved

### Step 2: Detect Related Issue

Attempt to detect a related GitHub issue using these strategies in order:

1. **Get branch name**:
   ```bash
   git branch --show-current
   ```

2. **Extract issue number from branch name**:
   ```bash
   # Handles: 107-feature, feature/107-name, feature-107, etc.
   echo "BRANCH_NAME_HERE" | grep -oE '[0-9]+' | head -1
   ```

3. **Validate issue exists** (if issue number found):
   ```bash
   gh issue view ISSUE_NUMBER --json number,title,state
   ```

4. **Fallback to user prompt**:
   - If no valid issue detected, ask: "Is this commit related to a GitHub issue? (Enter issue number or press Enter to skip)"

### Step 3: Construct Commit Message

Create a well-crafted commit message:

**Format:**
```
Adds [brief description of main changes]

- Detailed explanation of what was done
- Why it was done
- Any technical notes or context

Closes #XXX
```

**Key guidelines:**
- Use present tense ("Adds", "Fixes", "Updates")
- Subject line: Keep under 50 characters when possible
- Body: Wrap at 72 characters per line
- Be detailed and technical in the body
- Include `Closes #XXX` only if an issue was detected/validated

### Step 4: Present for Approval

Show the user the proposed commit:

```
I've analyzed your changes and prepared the following:

**Related Issue**: #107 - "Add project list endpoint" (detected from branch name)

**Git Commit Message**:
```
Adds project resource module

- Implements list, get, create, delete operations for projects
- Adds pagination support with cursor-based pagination
- Includes comprehensive test coverage
- Follows existing resource module patterns

Closes #107
```

**Files to commit**:
- lib/braintrust/resources/project.ex
- test/braintrust/resources/project_test.exs
- [... other modified files]

Shall I proceed with this commit?
```

### Step 5: Execute After Approval

1. **Run mix format** to ensure formatting:
   ```bash
   mix format
   ```

2. **Create git commit**:
   - Stage all relevant files
   - Create commit with the detailed message
   - Use HEREDOC for proper formatting:
     ```bash
     git commit -m "$(cat <<'EOF'
     Commit message here.

     - Details here

     Closes #XXX
     EOF
     )"
     ```

3. **Verify**:
   - Show result: `git log --oneline -n 1`

## Important Guidelines:

- **NEVER add co-author information or Claude attribution**
- Commits should be authored solely by the user
- Do not include "Generated with Claude" or "Co-Authored-By" lines
- Write commit messages as if the user wrote them
- Analyze ALL changes on the branch, not just session context
- Present everything for user approval BEFORE making changes
