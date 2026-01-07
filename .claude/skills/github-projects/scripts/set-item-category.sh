#!/bin/bash
set -euo pipefail

# Set the category field for a project item
# Usage: ./set-item-category.sh PVTI_xxx "Feature|Bug|Improvement|Technical debt|Documentation|Research"

if [ $# -ne 2 ]; then
  echo "Error: Item ID and Category are required" >&2
  echo "Usage: $0 PVTI_xxx \"Feature|Bug|Improvement|Technical debt|Documentation|Research\"" >&2
  exit 1
fi

ITEM_ID="$1"
CATEGORY="$2"

# Project configuration
PROJECT_ID="PVT_kwDOArMuY84BMFuv"
CATEGORY_FIELD_ID="PVTSSF_lADOArMuY84BMFuvzg7eft0"

# Map category to option ID
case "$CATEGORY" in
  "Feature")
    OPTION_ID="d060bbcf"
    ;;
  "Bug")
    OPTION_ID="4d270e92"
    ;;
  "Improvement")
    OPTION_ID="a9b1f704"
    ;;
  "Technical debt")
    OPTION_ID="61bd9539"
    ;;
  "Documentation")
    OPTION_ID="cef3f397"
    ;;
  "Research")
    OPTION_ID="5777c73d"
    ;;
  *)
    echo "Error: Invalid category '$CATEGORY'" >&2
    echo "Valid options: Feature, Bug, Improvement, Technical debt, Documentation, Research" >&2
    exit 1
    ;;
esac

# Set the field
gh project item-edit \
  --id "$ITEM_ID" \
  --project-id "$PROJECT_ID" \
  --field-id "$CATEGORY_FIELD_ID" \
  --single-select-option-id "$OPTION_ID"
