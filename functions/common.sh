#!/bin/bash

# ================================
# COMMON UTILITIES — COMMON.SH
# Shared functions for all modules
# ================================

FUNCTIONS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(dirname "$FUNCTIONS_DIR")"
OUTPUT_DIR="$SCRIPT_DIR/output"
DIRECTORY_FILE="$FUNCTIONS_DIR/directory.txt"
SELECTED_FILE_PATH="$FUNCTIONS_DIR/selected_file.txt"

mkdir -p "$OUTPUT_DIR"

# Detect CSV/TSV delimiter by inspecting the second line of a file
detect_delimiter() {
  local line
  line=$(head -n 2 "$1" | tail -n 1)
  if grep -q $'\t' <<< "$line"; then
    printf '\t'
  elif grep -q ';' <<< "$line"; then
    echo ";"
  else
    echo ","
  fi
}

# Read and validate the currently selected file.
# Normalizes CRLF → LF (handles Windows-origin files in WSL).
# Sets global $selected_file and $delimiter on success.
load_selected_file() {
  if [ ! -f "$SELECTED_FILE_PATH" ]; then
    whiptail --title "No file selected" --msgbox \
      "No file has been selected yet.\nPlease use 'File Search' first." 10 60
    return 1
  fi
  local _raw_path
  _raw_path=$(< "$SELECTED_FILE_PATH")
  if [ ! -f "$_raw_path" ]; then
    whiptail --title "File not found" --msgbox \
      "Selected file no longer exists:\n$_raw_path\n\nPlease use 'File Search' again." 12 70
    return 1
  fi
  # Preserve original path for display in reports
  selected_file_original="$_raw_path"
  # Normalize CRLF → LF into a tmpfile so all modules see clean data
  local _norm
  _norm=$(mktemp --suffix=.csv)
  tr -d '\r' < "$_raw_path" > "$_norm"
  selected_file="$_norm"
  trap "rm -f \"$_norm\"" EXIT
  delimiter=$(detect_delimiter "$selected_file")
  return 0
}

# Read working directory; exit 1 if not set
load_directory() {
  if [ ! -f "$DIRECTORY_FILE" ]; then
    whiptail --title "No directory set" --msgbox \
      "Working directory not configured.\nPlease use 'File Search' first." 10 60
    return 1
  fi
  directory=$(< "$DIRECTORY_FILE")
  return 0
}

# Show only real mounted drives (/mnt/[a-z]) and echo the chosen path.
# Falls back to / if no Windows drives are mounted (native Linux).
_drives_picker() {
  local title="$1"
  local -a entries=()
  for d in /mnt/[a-z]; do
    [ -d "$d" ] || continue
    local letter
    letter=$(basename "$d" | tr '[:lower:]' '[:upper:]')
    entries+=("$d" "Drive $letter:")
  done
  [ "${#entries[@]}" -eq 0 ] && entries+=("/" "Root filesystem /")
  whiptail --title "$title" \
    --menu "Select a drive:" 18 70 10 \
    "${entries[@]}" 3>&1 1>&2 2>&3
}

# Interactive file explorer with back/forward history and drive jumping.
# Usage: result=$(navigate_and_select "TITLE" [start_dir|"DRIVES"])
# Writes the selected file path to stdout; returns 1 if cancelled.
navigate_and_select() {
  local title="${1:-FILE SEARCH}"
  local start_mode="${2:-$HOME}"
  local current_dir

  if [[ "$start_mode" == "DRIVES" ]]; then
    current_dir=$(_drives_picker "$title")
    [ -z "$current_dir" ] && return 1
  else
    current_dir="$start_mode"
    [ ! -d "$current_dir" ] && current_dir="$HOME"
  fi

  while true; do
    local entries=()
    local content_count=0

    # --- Navigation controls ---
    local parent_dir
    parent_dir="$(dirname "$current_dir")"
    [ "$parent_dir" == "$current_dir" ] && parent_dir="(already at root)"
    entries+=("[Back]" "Go up: $parent_dir")
    entries+=("[Drives]" "Switch drive")

    # --- Subdirectories ---
    while IFS= read -r -d '' subdir; do
      entries+=("$(basename "$subdir")/" "[Directory]")
      ((content_count++))
    done < <(find "$current_dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null | sort -z)

    # --- CSV / TSV files ---
    while IFS= read -r -d '' f; do
      entries+=("$(basename "$f")" "[CSV/TSV file]")
      ((content_count++))
    done < <(find "$current_dir" -maxdepth 1 -mindepth 1 -type f \
      \( -iname "*.csv" -o -iname "*.tsv" \) -print0 2>/dev/null | sort -z)

    [ "$content_count" -eq 0 ] && \
      entries+=("(empty)" "No subdirectories or CSV/TSV files here")

    local sel
    sel=$(whiptail --title "$title" \
      --menu "Location: $current_dir" \
      24 90 14 \
      "${entries[@]}" 3>&1 1>&2 2>&3)

    [ -z "$sel" ] && return 1

    case "$sel" in

      "[Back]")
        local up
        up="$(dirname "$current_dir")"
        if [ "$up" == "/mnt" ] || [ "$up" == "$current_dir" ]; then
          # At drive root or filesystem root — return to drives picker
          local drive_sel
          drive_sel=$(_drives_picker "$title")
          [ -n "$drive_sel" ] && [ -d "$drive_sel" ] && current_dir="$drive_sel"
        else
          current_dir="$up"
        fi
        ;;

      "[Drives]")
        local drive_sel
        drive_sel=$(_drives_picker "SWITCH DRIVE")
        [ -n "$drive_sel" ] && [ -d "$drive_sel" ] && current_dir="$drive_sel"
        ;;

      "(empty)")
        ;;  # no-op, redisplay menu

      *)
        if [[ "$sel" == */ ]]; then
          current_dir="$current_dir/${sel%/}"
        else
          # File selected — write path to stdout and return
          local target="$current_dir/$sel"
          if [ -f "$target" ]; then
            echo "$target"
            return 0
          fi
        fi
        ;;
    esac
  done
}
