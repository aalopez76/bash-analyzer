#!/bin/bash

# ================================
# SEARCH & FILTER — SEARCH.SH
# ================================

# Strict mode: -u (unset vars) + pipefail (propagate pipe failures).
# 'errexit' intentionally omitted — see file-scan.sh for rationale.
set -uo pipefail

# shellcheck source=functions/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

load_selected_file || exit 0

# Build column options for menus (CSV-quoting-aware header parse, M6)
mapfile -t headers < <(head -n 1 "$selected_file" \
  | awk -v FPAT="$(csv_fpat "$delimiter")" "$AWK_UNQUOTE"'{ for (i = 1; i <= NF; i++) print unq($i) }')
options=()
for i in "${!headers[@]}"; do
  options+=("$((i+1))" "${headers[$i]}")
done

select_column() {
  whiptail --title "SELECT COLUMN" --menu "Columns:" 20 60 10 "${options[@]}" 3>&1 1>&2 2>&3
}

save_result() {
  local tmpresult="$1"
  local output_file="$2"
  local label="$3"
  local title="$4"

  whiptail --title "$title" --textbox "$tmpresult" 25 90

  if whiptail --title "SAVE RESULT" \
      --yes-button "Save" --no-button "Cancel" \
      --yesno "Save results to output file?" 8 55; then
    cp "$tmpresult" "$output_file"
    whiptail --msgbox "Saved to: output/$label" 8 60
  fi
}

# ================================
# Main action menu
# ================================
ACTION=$(whiptail --title "SEARCH & FILTER" --menu "Select an action:" 20 70 10 \
  "1" "Regex search" \
  "2" "Column filter (multi-condition)" \
  "3" "Sort by column" \
  "4" "Unique values" 3>&1 1>&2 2>&3)
[ -z "$ACTION" ] && exit 0

case "$ACTION" in

# -------------------------
# 1. Regex search
# -------------------------
"1")
  output_file="$OUTPUT_DIR/regex_result.txt"
  tmpresult=$(mktemp)
  trap 'rm -f "$tmpresult" "$selected_file"' EXIT

  scope=$(whiptail --title "REGEX SEARCH" --menu "Search scope:" 12 60 3 \
    "1" "All columns" \
    "2" "Specific column" \
    "3" "Multiple columns" 3>&1 1>&2 2>&3)
  [ -z "$scope" ] && exit 0

  col_index=""
  col_list=""
  scope_label=""

  case "$scope" in
    "2")
      col_index=$(select_column)
      [ -z "$col_index" ] && exit 0
      scope_label="Column: ${headers[$((col_index-1))]} (#$col_index)"
      ;;
    "3")
      checklist_opts=()
      for i in "${!headers[@]}"; do
        checklist_opts+=("$((i+1))" "${headers[$i]}" "OFF")
      done
      raw=$(whiptail --title "SELECT COLUMNS" --checklist \
        "Select columns to search (SPACE to toggle):" 20 70 10 \
        "${checklist_opts[@]}" 3>&1 1>&2 2>&3)
      [ -z "$raw" ] && exit 0
      col_list=$(echo "$raw" | tr -d '"')
      scope_label="Columns: $col_list"
      ;;
    *)
      scope_label="All columns"
      ;;
  esac

  regex=$(whiptail --inputbox "Enter regex pattern:" 10 60 3>&1 1>&2 2>&3)
  [ -z "$regex" ] && exit 0

  # Compute matching rows per scope; the report layout is shared (below).
  case "$scope" in
    "1")
      match_lines=$(tail -n +2 "$selected_file" | grep -Ei "$regex")
      ;;
    "2")
      match_lines=$(awk -v FPAT="$(csv_fpat "$delimiter")" -v idx="$col_index" -v re="$regex" "$AWK_UNQUOTE"'
        NR > 1 { if (unq($idx) ~ re) print }' "$selected_file")
      ;;
    "3")
      match_lines=$(awk -v FPAT="$(csv_fpat "$delimiter")" -v col_list="$col_list" -v re="$regex" "$AWK_UNQUOTE"'
        BEGIN { split(col_list, cols, " ") }
        NR > 1 {
          for (c in cols) {
            if (unq($cols[c]) ~ re) { print; break }
          }
        }
      ' "$selected_file")
      ;;
  esac

  if [ -z "$match_lines" ]; then match_count=0; else match_count=$(echo "$match_lines" | wc -l); fi
  {
    echo "REGEX SEARCH REPORT"
    echo "File      : $(basename "$selected_file_original")"
    echo "Date      : $(date)"
    echo "======================================================"
    echo "Pattern   : $regex"
    echo "Scope     : $scope_label"
    echo "Matches   : $match_count"
    echo ""
    head -n 1 "$selected_file"
    echo "$match_lines"
  } > "$tmpresult"

  save_result "$tmpresult" "$output_file" "regex_result.txt" "REGEX SEARCH"
  trap - EXIT
  rm -f "$tmpresult" "$selected_file"
  ;;

# -------------------------
# 2. Column filter (multi-condition)
# -------------------------
"2")
  output_file="$OUTPUT_DIR/condition_result.txt"
  tmpfile=$(mktemp)
  tmpresult=$(mktemp)
  trap 'rm -f "$tmpfile" "$tmpfile.filtered" "$tmpresult"' EXIT
  cp "$selected_file" "$tmpfile"

  condition_desc=""

  while true; do
    col_index=$(whiptail --title "SELECT COLUMN" --menu "Columns:" 20 70 12 \
      "${options[@]}" \
      "none" "Done, apply filter" 3>&1 1>&2 2>&3)
    [ -z "$col_index" ] && exit 0
    [[ "$col_index" == "none" ]] && break

    # Guard: reject non-numeric col_index (whiptail parsing edge case)
    if ! [[ "$col_index" =~ ^[0-9]+$ ]]; then
      whiptail --title "ERROR" --msgbox "Invalid column selection. Please try again." 8 50
      continue
    fi

    operator=$(whiptail --title "OPERATOR" --menu "Operator:" 15 60 6 \
      "==" "Equal to" \
      "!=" "Not equal to" \
      ">"  "Greater than" \
      "<"  "Less than" \
      ">=" "Greater than or equal" \
      "<=" "Less than or equal" 3>&1 1>&2 2>&3)
    [ -z "$operator" ] && exit 0

    value=$(whiptail --inputbox \
      "Value for column '${headers[$((col_index-1))]}' (#$col_index):" 10 70 3>&1 1>&2 2>&3)
    [ -z "$value" ] && continue

    condition_desc+="${headers[$((col_index-1))]} $operator \"$value\"; "

    # Safe AWK: pass user input as variables, never interpolate as code.
    # FPAT + unq() make the field comparison CSV-quoting-aware (M6).
    awk -v FPAT="$(csv_fpat "$delimiter")" -v idx="$col_index" -v op="$operator" -v val="$value" "$AWK_UNQUOTE"'
      NR == 1 { print; next }
      {
        field = unq($idx)
        if      (op == "==") result = (field == val)
        else if (op == "!=") result = (field != val)
        else if (op == ">")  result = (field+0 >  val+0)
        else if (op == "<")  result = (field+0 <  val+0)
        else if (op == ">=") result = (field+0 >= val+0)
        else if (op == "<=") result = (field+0 <= val+0)
        else                 result = 0
        if (result) print
      }
    ' "$tmpfile" > "$tmpfile.filtered"
    mv "$tmpfile.filtered" "$tmpfile"
  done

  count=$(awk 'END{ print (NR > 1) ? NR-1 : 0 }' "$tmpfile")

  {
    echo "COLUMN FILTER REPORT"
    echo "File       : $(basename "$selected_file_original")"
    echo "Date       : $(date)"
    echo "======================================================"
    echo "Conditions : ${condition_desc:-none}"
    echo "Records    : $count"
    echo ""
    cat "$tmpfile"
  } > "$tmpresult"

  save_result "$tmpresult" "$output_file" "condition_result.txt" "COLUMN FILTER"
  trap - EXIT
  rm -f "$tmpfile" "$tmpfile.filtered" "$tmpresult"
  ;;

# -------------------------
# 3. Sort by column
# -------------------------
"3")
  output_file="$OUTPUT_DIR/sort_result.txt"
  tmpresult=$(mktemp)

  sort_cols=()
  sort_desc=""

  # First column (required)
  col=$(select_column)
  [ -z "$col" ] && exit 0
  sort_cols+=("$col")
  sort_desc+="${headers[$((col-1))]} (#$col)"

  # Additional columns (optional)
  while whiptail --title "SORT COLUMNS" \
      --yes-button "Add column" --no-button "Apply sort" \
      --yesno "Sort key so far: $sort_desc\n\nAdd another sort column?" 10 70; do
    col=$(select_column)
    [ -z "$col" ] && break
    sort_cols+=("$col")
    sort_desc+=", ${headers[$((col-1))]} (#$col)"
  done

  # Build the sort keys against DECORATED positions (1..N), not the original
  # column indices: we prefix each row with its sort-key values below so the
  # physical sort is CSV-quoting-aware (M6) instead of relying on a
  # delimiter-splitting `sort -t`.
  sort_args=()
  pos=1
  for c in "${sort_cols[@]}"; do
    # Detect if column is numeric to sort correctly (quoting-aware)
    is_num=$(awk -v FPAT="$(csv_fpat "$delimiter")" -v idx="$c" "$AWK_UNQUOTE"'
      NR>1 && NF && unq($idx) !~ /^[[:space:]]*$/ {
        if (unq($idx) !~ /^-?[0-9]+([.][0-9]+)?$/) { print "no"; exit }
      }
      END { print "yes" }' "$selected_file")
    if [[ "$is_num" == "yes" ]]; then
      sort_args+=("-k${pos},${pos}n")
    else
      sort_args+=("-k${pos},${pos}")
    fi
    pos=$((pos + 1))
  done

  # Decorate–sort–undecorate: prefix each data row with its (unquoted) sort
  # keys separated by SOH (\x01, assumed absent from the data), sort on those
  # decorated positions, then strip the prefix. This keeps sorting correct even
  # when a sort column is a quoted field containing the delimiter.
  sep=$'\x01'
  nkeys=${#sort_cols[@]}
  sorted_data=$(awk -v FPAT="$(csv_fpat "$delimiter")" -v sep="$sep" -v cols="${sort_cols[*]}" "$AWK_UNQUOTE"'
      NR>1 && NF {
        n = split(cols, ca, " ")
        pre = ""
        for (k = 1; k <= n; k++) pre = pre unq($ca[k]) sep
        print pre $0
      }' "$selected_file" \
    | sort -t"$sep" "${sort_args[@]}" \
    | cut -d"$sep" -f"$((nkeys + 1))-")
  if [ -z "$sorted_data" ]; then result_count=0; else result_count=$(echo "$sorted_data" | wc -l); fi

  {
    echo "SORT REPORT"
    echo "File      : $(basename "$selected_file_original")"
    echo "Date      : $(date)"
    echo "======================================================"
    echo "Sorted by : $sort_desc"
    echo "Records   : $result_count"
    echo ""
    head -n 1 "$selected_file"
    echo "$sorted_data"
  } > "$tmpresult"

  save_result "$tmpresult" "$output_file" "sort_result.txt" "SORT"
  rm -f "$tmpresult"
  ;;

# -------------------------
# 4. Unique values
# -------------------------
"4")
  output_file="$OUTPUT_DIR/unique_result.txt"
  tmpresult=$(mktemp)
  trap 'rm -f "$tmpresult" "$selected_file"' EXIT

  col_index=$(select_column)
  [ -z "$col_index" ] && exit 0

  unique_values=$(awk -v FPAT="$(csv_fpat "$delimiter")" -v idx="$col_index" "$AWK_UNQUOTE"'
    NR > 1 { v = unq($idx); gsub(/^[ \t]+|[ \t]+$/, "", v); if (v ~ /[^[:space:]]/) print v }' \
    "$selected_file" | sort | uniq)
  if [ -z "$unique_values" ]; then unique_count=0; else unique_count=$(echo "$unique_values" | wc -l); fi

  {
    echo "UNIQUE VALUES REPORT"
    echo "File    : $(basename "$selected_file_original")"
    echo "Column  : ${headers[$((col_index-1))]} (#$col_index)"
    echo "Date    : $(date)"
    echo "======================================================"
    echo "Unique values: $unique_count"
    echo ""
    echo "$unique_values"
  } > "$tmpresult"

  save_result "$tmpresult" "$output_file" "unique_result.txt" "UNIQUE VALUES"
  trap - EXIT
  rm -f "$tmpresult" "$selected_file"
  ;;

esac
