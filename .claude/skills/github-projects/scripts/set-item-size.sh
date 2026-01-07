#!/bin/bash
set -euo pipefail

# Set the size field for a project item
# Usage: ./set-item-size.sh PVTI_xxx "XS|S|M|L|XL"

if [ $# -ne 2 ]; then
  echo "Error: Item ID and Size are required" >&2
  echo "Usage: $0 PVTI_xxx \"XS|S|M|L|XL\"" >&2
  exit 1
fi

ITEM_ID="$1"
SIZE="$2"

# Project configuration
PROJECT_ID="PVT_kwDOArMuY84BMFuv"
SIZE_FIELD_ID="PVTSSF_lADOArMuY84BMFuvzg7eNbg"

# Map size to option ID
case "$SIZE" in
  "XS")
    OPTION_ID="911790be"
    ;;
  "S")
    OPTION_ID="b277fb01"
    ;;
  "M")
    OPTION_ID="86db8eb3"
    ;;
  "L")
    OPTION_ID="853c8207"
    ;;
  "XL")
    OPTION_ID="2d0801e2"
    ;;
  *)
    echo "Error: Invalid size '$SIZE'" >&2
    echo "Valid options: XS, S, M, L, XL" >&2
    exit 1
    ;;
esac

# Set the field
gh project item-edit \
  --id "$ITEM_ID" \
  --project-id "$PROJECT_ID" \
  --field-id "$SIZE_FIELD_ID" \
  --single-select-option-id "$OPTION_ID"
