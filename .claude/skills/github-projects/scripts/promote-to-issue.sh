#!/bin/bash
set -euo pipefail

# Convert a draft issue to a real GitHub issue using GraphQL mutation
# CRITICAL: Must use Project Item ID (PVTI_xxx), NOT Draft Issue ID (DI_xxx)
# Usage: ./promote-to-issue.sh PVTI_xxx

if [ $# -ne 1 ]; then
  echo "Error: Project Item ID is required" >&2
  echo "Usage: $0 PVTI_xxx" >&2
  echo "Note: Use PVTI_ ID (not DI_ ID)" >&2
  exit 1
fi

ITEM_ID="$1"

# Validate it's a PVTI_ ID
if [[ ! "$ITEM_ID" =~ ^PVTI_ ]]; then
  echo "Error: ID must be a Project Item ID starting with 'PVTI_'" >&2
  echo "Got: $ITEM_ID" >&2
  exit 1
fi

# Project configuration
REPOSITORY_ID="R_kgDOQ1YEZQ"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Convert draft to issue via GraphQL mutation
echo "Promoting draft issue to real issue..." >&2
RESULT=$(gh api graphql -f query="
mutation {
  convertProjectV2DraftIssueItemToIssue(input: {
    itemId: \"$ITEM_ID\"
    repositoryId: \"$REPOSITORY_ID\"
  }) {
    item {
      id
      content {
        ... on Issue {
          id
          number
          url
        }
      }
    }
  }
}")

# Output the promotion result
echo "$RESULT"

# Move the item from "Backlog" to "Ready" status
echo "Moving item to 'Ready' status..." >&2
"$SCRIPT_DIR/set-item-status.sh" "$ITEM_ID" "Ready"

echo "Successfully promoted and moved to Ready status!" >&2
