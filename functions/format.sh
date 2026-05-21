#!/bin/bash

# ============================================================
# FORMAT & EXPORT — FORMAT.SH
# Structural integrity, null map, type inference,
# and multi-format export (Clean CSV, SQL, JSON, Markdown)
# ============================================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

load_selected_file || exit 0

report_file="$OUTPUT_DIR/format-report.txt"

IFS="$delimiter" read -ra headers <<< "$(head -n 1 "$selected_file")"
ncols="${#headers[@]}"
total_rows=$(awk 'NF' "$selected_file" | tail -n +2 | wc -l)

# ---- Structural integrity check ----
bad_rows=$(awk -F"$delimiter" -v expected="$ncols" '
  NR == 1 { next }
  NF == 0  { next }
  NF != expected { printf "  Row %d: found %d columns (expected %d)\n", NR, NF, expected }
' "$selected_file")
bad_count=$(echo "$bad_rows" | grep -c '.' 2>/dev/null || echo 0)
[ -z "$bad_rows" ] && bad_count=0

# ---- Type inference per column ----
type_inference=$(awk -F"$delimiter" -v ncols="$ncols" '
NR == 1 { next }
{
  for (i = 1; i <= ncols; i++) {
    val = $i; gsub(/^[ \t]+|[ \t]+$/, "", val)
    if (val == "" || val ~ /^(NA|N\/A|null|NULL|None)$/) {
      nulls[i]++
    } else {
      total[i]++
      if (val ~ /^-?[0-9]+$/)                              int_c[i]++
      else if (val ~ /^-?[0-9]*\.[0-9]+([eE][+-]?[0-9]+)?$/) float_c[i]++
      else if (val ~ /^(true|false|yes|no)$/i)             bool_c[i]++
      else if (val ~ /^[0-9]{4}[-\/][0-9]{1,2}[-\/][0-9]{1,2}/) date_c[i]++
      else                                                 text_c[i]++
    }
  }
}
END {
  for (i = 1; i <= ncols; i++) {
    n = total[i]
    nc = int_c[i] + float_c[i]
    if      (float_c[i] > 0 && nc == n)                  typ = "FLOAT"
    else if (int_c[i] > 0   && nc == n)                  typ = "INTEGER"
    else if (bool_c[i] > 0  && bool_c[i] == n)           typ = "BOOLEAN"
    else if (date_c[i] > 0  && date_c[i] >= n*0.8)       typ = "DATE"
    else if (n == 0)                                      typ = "EMPTY"
    else                                                  typ = "TEXT"
    null_pct = (nulls[i]+0) / ((total_rows > 0) ? total_rows : 1) * 100
    printf "%d|%s|%d|%.1f\n", i, typ, (nulls[i]+0), null_pct
  }
}' total_rows="$total_rows" "$selected_file")

# ---- Build report ----
{
  echo "FORMAT & EXPORT REPORT"
  echo "File      : $(basename "$selected_file_original")"
  echo "Date      : $(date)"
  echo "Data rows : $total_rows  |  Columns: $ncols"
  echo "======================================================"
  echo ""

  echo "STRUCTURAL INTEGRITY"
  echo "  Expected columns per row: $ncols"
  if [ "$bad_count" -gt 0 ]; then
    echo "  Malformed rows found: $bad_count"
    echo "$bad_rows"
  else
    echo "  All rows have correct column count. OK"
  fi
  echo ""

  echo "NULL MAP & TYPE INFERENCE"
  printf "  %-4s %-20s %-10s %s\n" "Col" "Name" "Type" "Nulls"
  echo "  ------------------------------------------------------------"

  while IFS='|' read -r idx typ null_count null_pct; do
    col_name="${headers[$((idx-1))]}"
    filled=$(awk "BEGIN { printf \"%d\", ($null_pct / 100) * 15 }")
    bar=""
    for ((b=0; b<filled; b++));    do bar+="█"; done
    for ((b=filled; b<15; b++)); do bar+="░"; done
    printf "  %-4s %-20s %-10s %3d (%5.1f%%) %s\n" \
      "#$idx" "$col_name" "$typ" "$null_count" "$null_pct" "$bar"
  done <<< "$type_inference"

  echo ""
  echo "======================================================"
} > "$report_file"

whiptail --title "FORMAT & EXPORT REPORT" --scrolltext --msgbox "$(cat "$report_file")" 30 100

# ============================================================
# EXPORT MENU — Multi-format export
# ============================================================

export_action=$(whiptail --title "FORMAT & EXPORT" --menu \
  "Choose an export format:" 16 70 5 \
  "1" "Clean CSV     — remove malformed rows, fill nulls" \
  "2" "SQL INSERTs   — generate INSERT statements" \
  "3" "JSON array    — export as JSON" \
  "4" "Markdown table — export as .md table" \
  "5" "Skip export" \
  3>&1 1>&2 2>&3)
[ -z "$export_action" ] && exit 0

case "$export_action" in

# ---- 1. Clean CSV ----
"1")
  clean_file="$OUTPUT_DIR/clean_result.csv"

  fill_value=$(whiptail --inputbox \
    "Replace null/empty values with (leave blank to keep as-is):" \
    10 70 "NA" 3>&1 1>&2 2>&3)
  [ $? -ne 0 ] && fill_value="NA"

  awk -F"$delimiter" -v OFS="$delimiter" -v ncols="$ncols" \
    -v fill="$fill_value" '
  NR == 1 { print; next }
  NF != ncols { next }           # remove malformed rows
  {
    for (i = 1; i <= NF; i++) {
      val = $i; gsub(/^[ \t]+|[ \t]+$/, "", val)
      if (val == "" || val ~ /^(NA|N\/A|null|NULL|None)$/) $i = fill
    }
    print
  }' "$selected_file" > "$clean_file"

  clean_rows=$(awk 'NF' "$clean_file" | tail -n +2 | wc -l)
  whiptail --title "EXPORT COMPLETE" --msgbox \
    "Clean CSV saved to:\n  output/clean_result.csv\n\nData rows exported: $clean_rows\nMalformed rows removed: $bad_count" \
    12 70
  ;;

# ---- 2. SQL INSERT statements ----
"2")
  base_name=$(basename "$selected_file_original")
  base_name="${base_name%.*}"

  table_name=$(whiptail --inputbox \
    "Table name for SQL INSERT statements:" 10 60 "$base_name" 3>&1 1>&2 2>&3)
  [ -z "$table_name" ] && exit 0

  timestamp=$(date +%Y%m%d_%H%M%S)
  sql_file="$OUTPUT_DIR/export_${base_name}_${timestamp}.sql"

  awk -F"$delimiter" -v tbl="$table_name" '
  NR == 1 {
    ncols = NF
    cols = ""
    for (i = 1; i <= NF; i++) cols = cols (i > 1 ? ", " : "") $i
    next
  }
  {
    vals = ""
    for (i = 1; i <= ncols; i++) {
      v = (i <= NF) ? $i : ""
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      if (v ~ /^-?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$/) {
        vals = vals (i > 1 ? ", " : "") v
      } else if (v == "" || v ~ /^(NA|N\/A|null|NULL|None)$/) {
        vals = vals (i > 1 ? ", " : "") "NULL"
      } else {
        gsub(/\047/, "\047\047", v)  # escape single quotes
        vals = vals (i > 1 ? ", " : "") "\047" v "\047"
      }
    }
    printf "INSERT INTO %s (%s) VALUES (%s);\n", tbl, cols, vals
  }' "$selected_file" > "$sql_file"

  sql_lines=$(wc -l < "$sql_file")
  whiptail --title "EXPORT COMPLETE" --msgbox \
    "SQL export saved to:\n  output/$(basename "$sql_file")\n\nTable   : $table_name\nINSERTs : $sql_lines" \
    12 70
  ;;

# ---- 3. JSON array ----
"3")
  base_name=$(basename "$selected_file_original")
  base_name="${base_name%.*}"
  timestamp=$(date +%Y%m%d_%H%M%S)
  json_file="$OUTPUT_DIR/export_${base_name}_${timestamp}.json"

  awk -F"$delimiter" '
  NR == 1 {
    ncols = NF
    for (i = 1; i <= NF; i++) headers[i] = $i
    print "["
    next
  }
  {
    if (prev != "") print prev ","
    obj = "  {"
    for (i = 1; i <= ncols; i++) {
      v = (i <= NF) ? $i : ""
      gsub(/^[ \t]+|[ \t]+$/, "", v)
      gsub(/\\/, "\\\\", v)
      gsub(/"/, "\\\"", v)
      k = headers[i]
      sep = (i > 1) ? ", " : ""
      if (v ~ /^-?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$/)
        obj = obj sep "\"" k "\": " v
      else if (v == "" || v ~ /^(NA|N\/A|null|NULL|None)$/)
        obj = obj sep "\"" k "\": null"
      else
        obj = obj sep "\"" k "\": \"" v "\""
    }
    obj = obj "}"
    prev = obj
  }
  END { if (prev != "") print prev; print "]" }
  ' "$selected_file" > "$json_file"

  json_lines=$(wc -l < "$json_file")
  whiptail --title "EXPORT COMPLETE" --msgbox \
    "JSON export saved to:\n  output/$(basename "$json_file")\n\nRecords : $total_rows\nLines   : $json_lines" \
    12 70
  ;;

# ---- 4. Markdown table ----
"4")
  base_name=$(basename "$selected_file_original")
  base_name="${base_name%.*}"
  timestamp=$(date +%Y%m%d_%H%M%S)
  md_file="$OUTPUT_DIR/export_${base_name}_${timestamp}.md"

  awk -F"$delimiter" '
  NR == 1 {
    ncols = NF
    printf "|"
    for (i = 1; i <= NF; i++) printf " %s |", $i
    print ""
    printf "|"
    for (i = 1; i <= NF; i++) printf " --- |"
    print ""
    next
  }
  {
    printf "|"
    for (i = 1; i <= ncols; i++) {
      v = (i <= NF) ? $i : ""
      gsub(/\|/, "\\|", v)
      printf " %s |", v
    }
    print ""
  }' "$selected_file" > "$md_file"

  md_lines=$(wc -l < "$md_file")
  whiptail --title "EXPORT COMPLETE" --msgbox \
    "Markdown export saved to:\n  output/$(basename "$md_file")\n\nRecords : $total_rows\nLines   : $md_lines" \
    12 70
  ;;

# ---- 5. Skip ----
"5")
  ;;

esac
