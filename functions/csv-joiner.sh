#!/bin/bash

# ================================
# CSV JOINER — CSV-JOINER.SH
# SQL-style JOIN between two CSV/TSV files
# ================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# ---- Load primary file ----
load_selected_file || exit 0
primary_file="$selected_file"
primary_delimiter="$delimiter"
primary_file_original="$selected_file_original"

IFS="$primary_delimiter" read -ra primary_headers <<< "$(head -n 1 "$primary_file")"
primary_ncols="${#primary_headers[@]}"

# ---- Select secondary file using shared navigator ----
# Start from saved directory so user doesn't have to navigate from $HOME
load_directory 2>/dev/null
start_nav="${directory:-DRIVES}"
secondary_raw=$(navigate_and_select "SELECT SECONDARY FILE" "$start_nav")
[ -z "$secondary_raw" ] && exit 0

# Normalize CRLF in secondary file (same as primary)
secondary_norm=$(mktemp --suffix=.csv)
tr -d '\r' < "$secondary_raw" > "$secondary_norm"
trap "rm -f \"$secondary_norm\"" EXIT

secondary_file="$secondary_norm"
secondary_delimiter=$(detect_delimiter "$secondary_file")
IFS="$secondary_delimiter" read -ra secondary_headers <<< "$(head -n 1 "$secondary_file")"
secondary_ncols="${#secondary_headers[@]}"

# ---- Select JOIN type ----
join_type=$(whiptail --title "JOIN TYPE" --menu "Select JOIN type:" 14 60 4 \
  "INNER" "Only rows matching in both files" \
  "LEFT"  "All primary rows + matching secondary" \
  "RIGHT" "All secondary rows + matching primary" \
  "FULL"  "All rows from both files" \
  3>&1 1>&2 2>&3)
[ -z "$join_type" ] && exit 0

# ---- Select key columns ----
primary_opts=()
for i in "${!primary_headers[@]}"; do
  primary_opts+=("$((i+1))" "${primary_headers[$i]}")
done
primary_key=$(whiptail --title "PRIMARY KEY" \
  --menu "Key column in: $(basename "$primary_file")" \
  20 70 10 "${primary_opts[@]}" 3>&1 1>&2 2>&3)
[ -z "$primary_key" ] && exit 0

secondary_opts=()
for i in "${!secondary_headers[@]}"; do
  secondary_opts+=("$((i+1))" "${secondary_headers[$i]}")
done
secondary_key=$(whiptail --title "SECONDARY KEY" \
  --menu "Key column in: $(basename "$secondary_file")" \
  20 70 10 "${secondary_opts[@]}" 3>&1 1>&2 2>&3)
[ -z "$secondary_key" ] && exit 0

# ---- Execute JOIN ----
# Uses split() to handle different delimiters per file without FS conflicts.
# All rows stored in associative arrays keyed by join column (string comparison).
# Output is always comma-separated CSV.

join_csv="$OUTPUT_DIR/join_result.csv"
join_report="$OUTPUT_DIR/join_result.txt"

awk -v pk="$primary_key" -v sk="$secondary_key" \
    -v jtype="$join_type" \
    -v pdelim="$primary_delimiter" -v sdelim="$secondary_delimiter" \
    -v pncols="$primary_ncols" -v sncols="$secondary_ncols" \
    -v pfile="$primary_file" '
BEGIN { OFS = "," }

# --- Load primary file ---
FILENAME == pfile {
  n = split($0, f, pdelim)
  if (FNR == 1) {
    # Build header (all primary columns)
    p_header = f[1]
    for (i = 2; i <= n; i++) p_header = p_header "," f[i]
    next
  }
  key = f[pk]; gsub(/^[ \t]+|[ \t]+$/, "", key)
  row = f[1]
  for (i = 2; i <= n; i++) row = row "," f[i]
  p_rows[key] = (p_rows[key] != "") ? p_rows[key] SUBSEP row : row
  p_seen[key] = 1
  next
}

# --- Load secondary file ---
{
  n = split($0, f, sdelim)
  if (FNR == 1) {
    # Build secondary header excluding the key column
    s_header = ""
    for (i = 1; i <= n; i++) {
      if (i != sk) s_header = s_header (s_header != "" ? "," : "") f[i]
    }
    next
  }
  key = f[sk]; gsub(/^[ \t]+|[ \t]+$/, "", key)
  row = ""
  for (i = 1; i <= n; i++) {
    if (i != sk) row = row (row != "" ? "," : "") f[i]
  }
  s_rows[key] = (s_rows[key] != "") ? s_rows[key] SUBSEP row : row
  s_seen[key] = 1
}

END {
  # Print combined header
  print p_header "," s_header

  # Build empty placeholders
  empty_p = ""; for (i = 1; i <= pncols; i++) empty_p = empty_p (i>1 ? "," : "")
  empty_s = ""; for (i = 1; i <= sncols-1; i++) empty_s = empty_s (i>1 ? "," : "")

  # --- INNER + LEFT + FULL: iterate primary ---
  if (jtype == "INNER" || jtype == "LEFT" || jtype == "FULL") {
    for (key in p_seen) {
      n_pr = split(p_rows[key], pr, SUBSEP)
      if (key in s_seen) {
        n_sr = split(s_rows[key], sr, SUBSEP)
        for (a = 1; a <= n_pr; a++)
          for (b = 1; b <= n_sr; b++)
            print pr[a] "," sr[b]
        matched[key] = 1
      } else if (jtype == "LEFT" || jtype == "FULL") {
        for (a = 1; a <= n_pr; a++) print pr[a] "," empty_s
      }
    }
  }

  # --- RIGHT + FULL: unmatched secondary rows ---
  if (jtype == "RIGHT" || jtype == "FULL") {
    for (key in s_seen) {
      if (key in matched) continue
      if (jtype == "RIGHT" && key in p_seen) {
        # RIGHT JOIN: include ALL secondary, even those with primary matches
        n_pr = split(p_rows[key], pr, SUBSEP)
        n_sr = split(s_rows[key], sr, SUBSEP)
        for (a = 1; a <= n_pr; a++)
          for (b = 1; b <= n_sr; b++)
            print pr[a] "," sr[b]
      } else {
        n_sr = split(s_rows[key], sr, SUBSEP)
        for (b = 1; b <= n_sr; b++) print empty_p "," sr[b]
      }
    }
  }
}
' "$primary_file" "$secondary_file" > "$join_csv"

join_rows=$(($(wc -l < "$join_csv") - 1))

{
  echo "CSV JOINER REPORT"
  echo "Primary   : $(basename "$primary_file_original")"
  echo "Secondary : $(basename "$secondary_raw")"
  echo "Join type : $join_type"
  echo "Key (P)   : ${primary_headers[$((primary_key-1))]} (#$primary_key)"
  echo "Key (S)   : ${secondary_headers[$((secondary_key-1))]} (#$secondary_key)"
  echo "Date      : $(date)"
  echo "======================================================"
  echo "Result rows: $join_rows"
  echo ""
  echo "Preview (first 20 rows):"
  head -n 21 "$join_csv"
} > "$join_report"

whiptail --title "JOIN RESULT" --scrolltext --msgbox "$(cat "$join_report")" 30 100
whiptail --msgbox "Join saved to:\n  output/join_result.csv  ($join_rows rows)\n  output/join_result.txt  (report)" 10 70

# Save original path to restore after sub-module runs
_original_selected=$(<"$SELECTED_FILE_PATH")

# ---- Post-JOIN sub-menu ----
while true; do
  post=$(whiptail --title "ANALYZE JOIN RESULT" \
    --menu "Run analysis on the joined dataset:" 16 70 4 \
    "1" "File Scan" \
    "2" "Data Quality" \
    "3" "Search & Filter" \
    "4" "Done" 3>&1 1>&2 2>&3)
  [ -z "$post" ] && break

  case "$post" in
    1)
      echo "$join_csv" > "$SELECTED_FILE_PATH"
      bash "$FUNCTIONS_DIR/file-scan.sh"
      echo "$_original_selected" > "$SELECTED_FILE_PATH"
      ;;
    2)
      echo "$join_csv" > "$SELECTED_FILE_PATH"
      bash "$FUNCTIONS_DIR/data-quality.sh"
      echo "$_original_selected" > "$SELECTED_FILE_PATH"
      ;;
    3)
      echo "$join_csv" > "$SELECTED_FILE_PATH"
      bash "$FUNCTIONS_DIR/search.sh"
      echo "$_original_selected" > "$SELECTED_FILE_PATH"
      ;;
    4) break ;;
  esac
done

