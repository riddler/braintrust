#!/bin/bash
set -euo pipefail

# Set the priority field for a project item
# Usage: ./set-item-priority.sh PVTI_xxx "P0|P1|P2"

if [ $# -ne 2 ]; then
  echo "Error: Item ID and Priority are required" >&2
  echo "Usage: $0 PVTI_xxx \"P0|P1|P2\"" >&2
  exit 1
fi

ITEM_ID="$1"
PRIORITY="$2"

# Project configuration
PROJECT_ID="PVT_kwDOArMuY84BMFuv"
PRIORITY_FIELD_ID="PVTSSF_lADOArMuY84BMFuvzg7eNbc"

# Map priority to option ID
case "$PRIORITY" in
  "P0")
    OPTION_ID="79628723"
    ;;
  "P1")
    OPTION_ID="0a877460"
    ;;
  "P2")
    OPTION_ID="da944a9c"
    ;;
  *)
    echo "Error: Invalid priority '$PRIORITY'" >&2
    echo "Valid options: P0, P1, P2" >&2
    exit 1
    ;;
esac

# Set the field
gh project item-edit \
  --id "$ITEM_ID" \
  --project-id "$PROJECT_ID" \
  --field-id "$PRIORITY_FIELD_ID" \
  --single-select-option-id "$OPTION_ID"
