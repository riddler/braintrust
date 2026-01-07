#!/bin/bash
set -euo pipefail

# Set the status field for a project item
# Usage: ./set-item-status.sh PVTI_xxx "Backlog|Ready|In progress|In review|Done"

if [ $# -ne 2 ]; then
  echo "Error: Item ID and Status are required" >&2
  echo "Usage: $0 PVTI_xxx \"Backlog|Ready|In progress|In review|Done\"" >&2
  exit 1
fi

ITEM_ID="$1"
STATUS="$2"

# Project configuration
PROJECT_ID="PVT_kwDOArMuY84BMFuv"
STATUS_FIELD_ID="PVTSSF_lADOArMuY84BMFuvzg7eNWc"

# Map status to option ID
case "$STATUS" in
  "Backlog")
    OPTION_ID="f75ad846"
    ;;
  "Ready")
    OPTION_ID="e18bf179"
    ;;
  "In progress")
    OPTION_ID="47fc9ee4"
    ;;
  "In review")
    OPTION_ID="aba860b9"
    ;;
  "Done")
    OPTION_ID="98236657"
    ;;
  *)
    echo "Error: Invalid status '$STATUS'" >&2
    echo "Valid options: Backlog, Ready, In progress, In review, Done" >&2
    exit 1
    ;;
esac

# Set the field
gh project item-edit \
  --id "$ITEM_ID" \
  --project-id "$PROJECT_ID" \
  --field-id "$STATUS_FIELD_ID" \
  --single-select-option-id "$OPTION_ID"
