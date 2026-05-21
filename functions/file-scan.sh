#!/bin/bash

# ================================
# FILE SCAN — FILE-SCAN.SH
# ================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

output_file="$OUTPUT_DIR/scan-report.txt"

load_selected_file || exit 0
files=("$selected_file")
check_duplicates_single=true

classify_columns() {
  local file="$1" delimiter="$2"
  awk -F"$delimiter" '
  NR == 1 { for (i = 1; i <= NF; i++) { header[i] = $i; ncols = NF } next }
  {
    for (i = 1; i <= NF; i++) {
      if ($i !~ /^-?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$/) nonnum[i]++
      total[i]++
    }
  }
  END {
    for (i = 1; i <= ncols; i++) {
      tipo = (nonnum[i] > 0) ? "NON-NUMERIC" : "NUMERIC"
      printf "  Column %d (%s): %s\n", i, header[i], tipo
    }
  }' "$file"
}

# Lines preview option
lines_view=$(whiptail --radiolist "Lines to show in preview:" 15 60 4 \
  "H" "Head" ON \
  "T" "Tail" OFF \
  "B" "Both (head + tail)" OFF \
  "N" "None" OFF 3>&1 1>&2 2>&3)
[[ -z "$lines_view" ]] && exit 0

if [[ "$lines_view" != "N" ]]; then
  num_lines=$(whiptail --inputbox "Number of lines to display (default 5):" 10 60 5 3>&1 1>&2 2>&3)
  [[ $? -ne 0 ]] && exit 0
  [[ -z "$num_lines" ]] && num_lines=5
else
  num_lines=0
fi

# Initialize report
{
  echo "FILE SCAN REPORT"
  echo "File      : $(basename "$selected_file_original")"
  echo "Directory : $(dirname "$selected_file_original")"
  echo "Generated : $(date)"
  echo "======================================================"
  echo ""
} > "$output_file"

declare -A file_hashes
declare -A duplicate_groups
group_counter=1

for file in "${files[@]}"; do
  base=$(basename "$selected_file_original")
  delimiter=$(detect_delimiter "$file")
  [[ "$delimiter" == $'\t' ]] && delimname="Tab" || delimname="$delimiter"

  rows=$(awk 'NF' "$file" | tail -n +2 | wc -l)   # skip blank lines, exclude header
  cols=$(head -n 1 "$file" | awk -F"$delimiter" '{print NF}')

  {
    echo "File      : $base"
    echo "Delimiter : $delimname"
    echo "Data rows : $rows"
    echo "Columns   : $cols"
    echo ""
  } >> "$output_file"

  if [[ "$lines_view" == "H" || "$lines_view" == "B" ]]; then
    echo "Head ($num_lines lines):" >> "$output_file"
    head -n "$((num_lines + 1))" "$file" >> "$output_file"
    echo "" >> "$output_file"
  fi

  if [[ "$lines_view" == "T" || "$lines_view" == "B" ]]; then
    echo "Tail ($num_lines lines):" >> "$output_file"
    { head -n 1 "$file"; tail -n "$num_lines" "$file"; } >> "$output_file"
    echo "" >> "$output_file"
  fi

  echo "Column types:" >> "$output_file"
  classify_columns "$file" "$delimiter" >> "$output_file"

  # Hash for duplicate detection
  hash=$(sha256sum "$file" | awk '{print $1}')
  original_base=$(basename "$selected_file_original")
  if [[ -n "${file_hashes[$hash]}" ]]; then
    duplicate_groups["$hash"]+=$'\n'"$original_base"
  else
    file_hashes["$hash"]="1"
    duplicate_groups["$hash"]="$original_base"
  fi

  echo -e "\n------------------------------------------------------\n" >> "$output_file"
done

# Single-file mode: compare hash against all other files in directory
if [[ "$check_duplicates_single" == true ]]; then
  local_dir=$(dirname "$selected_file_original")
  # Hash the normalized copy (CRLF already stripped)
  original_hash=$(sha256sum "$selected_file" | awk '{print $1}')
  for other_file in "$local_dir"/*.csv "$local_dir"/*.tsv; do
    [[ "$(realpath "$other_file" 2>/dev/null)" == "$(realpath "$selected_file_original" 2>/dev/null)" ]] && continue
    [[ ! -f "$other_file" ]] && continue
    # Normalize CRLF before hashing so comparison is fair with the normalized selected file
    other_hash=$(tr -d '\r' < "$other_file" | sha256sum | awk '{print $1}')
    if [[ "$original_hash" == "$other_hash" ]]; then
      duplicate_groups["$original_hash"]+=$'\n'"$(basename "$other_file")"
    fi
  done
fi

# Duplicate report
{
  echo "DUPLICATE CHECK (by content hash):"
  dupes_found=0
  for hash in "${!duplicate_groups[@]}"; do
    group="${duplicate_groups[$hash]}"
    member_count=$(grep -c '^' <<< "$group")
    if [[ "$member_count" -gt 1 ]]; then
      echo "  Duplicate group $group_counter:"
      echo "$group" | sed 's/^/    /'
      echo ""
      ((group_counter++))
      ((dupes_found++))
    fi
  done
  [[ "$dupes_found" -eq 0 ]] && echo "  No duplicate files found."
} >> "$output_file"

whiptail --title "FILE SCAN REPORT" --scrolltext --msgbox "$(cat "$output_file")" 30 100
