#!/bin/bash
set -euo pipefail

# List all backlog items in the GitHub Project
# Usage: ./list-backlog-items.sh [limit]

LIMIT="${1:-50}"

# Project configuration
PROJECT_NUMBER=3
OWNER="riddler"

# List only backlog items
# Note: We fetch a larger limit first since filtering happens after fetching
FETCH_LIMIT=$((LIMIT * 3))

gh project item-list "$PROJECT_NUMBER" \
  --owner "$OWNER" \
  --format json \
  --limit "$FETCH_LIMIT" \
  --jq '{items: [.items[] | select(.status == "Backlog")] | .[0:'"$LIMIT"'], totalCount: ([.items[] | select(.status == "Backlog")] | length)}'
