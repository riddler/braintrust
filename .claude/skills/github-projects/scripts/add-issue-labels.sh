#!/bin/bash
set -euo pipefail

# Add labels to a GitHub issue
# Usage: ./add-issue-labels.sh <issue-number> <label1> [label2] [label3] ...

if [ $# -lt 2 ]; then
  echo "Error: Issue number and at least one label are required" >&2
  echo "Usage: $0 <issue-number> <label1> [label2] [label3] ..." >&2
  exit 1
fi

ISSUE_NUMBER="$1"
shift  # Remove first argument, leaving just labels

REPO="riddler/braintrust"

# Add each label
for LABEL in "$@"; do
  gh issue edit "$ISSUE_NUMBER" \
    --add-label "$LABEL" \
    --repo "$REPO"
done

echo "Added labels to issue #$ISSUE_NUMBER: $*"
