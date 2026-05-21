#!/bin/bash

# ================================
# FILE SEARCH — FILE-SEARCH.SH
# Navigate the filesystem and set the active CSV/TSV file
# ================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Restore last used directory as the starting point
start_dir="$HOME"
if [ -f "$DIRECTORY_FILE" ]; then
  saved=$(< "$DIRECTORY_FILE")
  [ -d "$saved" ] && start_dir="$saved"
fi

selected=$(navigate_and_select "FILE SEARCH" "$start_dir")
[ -z "$selected" ] && exit 0

# Persist state
echo "$(dirname "$selected")" > "$DIRECTORY_FILE"
echo "$selected" > "$SELECTED_FILE_PATH"

# Confirmation summary
delimiter=$(detect_delimiter "$selected")
[[ "$delimiter" == $'\t' ]] && delimname="Tab" || delimname="$delimiter"
rows=$(($(wc -l < "$selected") - 1))
cols=$(head -n 1 "$selected" | awk -F"$delimiter" '{print NF}')

whiptail --title "FILE SELECTED" --msgbox \
  "Active file set to:\n$selected\n\nDelimiter : $delimname\nData rows : $rows\nColumns   : $cols" \
  14 70
