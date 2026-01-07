#!/bin/bash
set -euo pipefail

# Create a new draft item in the GitHub Project
# Usage: ./create-draft-item.sh "Title" "Body"

if [ $# -lt 1 ]; then
  echo "Error: Title is required" >&2
  echo "Usage: $0 \"Title\" [\"Body\"]" >&2
  exit 1
fi

TITLE="$1"
BODY="${2:-}"

# Project configuration
PROJECT_NUMBER=3
OWNER="riddler"

# Create the draft item
gh project item-create "$PROJECT_NUMBER" \
  --owner "$OWNER" \
  --title "$TITLE" \
  --body "$BODY" \
  --format json
