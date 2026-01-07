#!/bin/bash
set -euo pipefail

# Update the title and/or body of a draft issue
# CRITICAL: Must use Draft Issue ID (DI_xxx), NOT Project Item ID (PVTI_xxx)
# CRITICAL: Must always provide both title and body (API requirement)
# Usage: ./update-draft-content.sh DI_xxx "Title" "Body"

if [ $# -ne 3 ]; then
  echo "Error: Draft Issue ID, Title, and Body are required" >&2
  echo "Usage: $0 DI_xxx \"Title\" \"Body\"" >&2
  echo "Note: Use DI_ ID (not PVTI_ ID)" >&2
  exit 1
fi

DRAFT_ID="$1"
TITLE="$2"
BODY="$3"

# Validate it's a DI_ ID
if [[ ! "$DRAFT_ID" =~ ^DI_ ]]; then
  echo "Error: ID must be a Draft Issue ID starting with 'DI_'" >&2
  echo "Got: $DRAFT_ID" >&2
  exit 1
fi

# Project configuration
PROJECT_ID="PVT_kwDOArMuY84BMFuv"

# Update the draft
gh project item-edit \
  --id "$DRAFT_ID" \
  --project-id "$PROJECT_ID" \
  --title "$TITLE" \
  --body "$BODY"
