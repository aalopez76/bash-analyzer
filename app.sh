#!/bin/bash

#======================================
# BASH DATA ANALYZER — MAIN SCRIPT
#======================================

command -v whiptail >/dev/null 2>&1 || { echo >&2 "whiptail is not installed. Aborting."; exit 1; }

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
functions_dir="$script_dir/functions"
output_dir="$script_dir/output"
mkdir -p "$output_dir"

# Load shared utilities
source "$functions_dir/common.sh"

# ---- Screen 1: Welcome / confirm ----
whiptail --title "BASH DATA ANALYZER" \
  --yes-button "Select File" --no-button "Cancel" \
  --yesno "Select a CSV or TSV file to begin analysis." \
  10 60
[ $? -ne 0 ] && exit 0

# ---- Screen 2: File explorer (starts at drives list) ----
selected=$(navigate_and_select "FILE SEARCH" "DRIVES")
[ -z "$selected" ] && exit 0

# Persist state for child modules
echo "$(dirname "$selected")" > "$DIRECTORY_FILE"
echo "$selected"               > "$SELECTED_FILE_PATH"

active_name=$(basename "$selected")

# ---- Screen 3: Main menu (6 analysis options) ----
display_menu() {
  while true; do
    choice=$(whiptail --nocancel \
      --title "BASH DATA ANALYZER  |  $active_name" \
      --menu "Active file: $selected\n\nChoose an action:" 20 90 6 \
      "1" "File Scan       — structure, columns & duplicates" \
      "2" "Data Quality    — nulls, types & anomalies" \
      "3" "Search & Filter — regex, conditions, sort, unique" \
      "4" "CSV Joiner      — SQL-style JOIN between two files" \
      "5" "Format & Export — integrity, clean CSV, SQL, JSON, Markdown" \
      "6" "Exit" \
      3>&1 1>&2 2>&3)

    [ -z "$choice" ] && break

    case "$choice" in
      1) bash "$functions_dir/file-scan.sh" ;;
      2) bash "$functions_dir/data-quality.sh" ;;
      3) bash "$functions_dir/search.sh" ;;
      4) bash "$functions_dir/csv-joiner.sh" ;;
      5) bash "$functions_dir/format.sh" ;;
      6) whiptail --title "Exit" --msgbox "Session ended." 8 40; break ;;
      *) break ;;
    esac
  done
}

display_menu

[ -f "$script_dir/move.sh" ] && bash "$script_dir/move.sh"
