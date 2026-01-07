---
description: Create GitHub Project items for the Braintrust backlog.
---

Invoke the `github-projects` skill to create a new backlog item:

```
Skill(skill: "github-projects")
```

Context: Create a new backlog item with these details: $ARGUMENTS

If no arguments are provided, ask the user for:
- Title (action-oriented)
- Category (Feature/Bug/Improvement/Technical debt/Documentation/Research)
- Size (XS/S/M/L/XL)
- Priority (Critical/High/Medium/Low)
