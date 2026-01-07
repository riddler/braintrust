---
description: Create GitHub issues with intelligent analysis and tagging
---

Invoke the `github-projects` skill to create a new GitHub issue:

```
Skill(skill: "github-projects")
```

Context: Create a new GitHub issue directly (not from backlog) with these details: $ARGUMENTS

**Note**: To promote an existing backlog item to an issue, use `/promote_item` instead.

If no arguments are provided, ask the user for:
- A brief title or description of the issue
- Any additional context, requirements, or details
- (Optional) Related files, components, or areas of the codebase
