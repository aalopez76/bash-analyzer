#!/bin/bash

# ================================
# DATA QUALITY — DATA-QUALITY.SH
# Nulls, type anomalies, whitespace, duplicate rows
# ================================

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

load_selected_file || exit 0

output_file="$OUTPUT_DIR/quality-report.txt"
total_rows=$(awk 'NF' "$selected_file" | tail -n +2 | wc -l)

{
  echo "DATA QUALITY REPORT"
  echo "File      : $(basename "$selected_file_original")"
  echo "Directory : $(dirname "$selected_file_original")"
  echo "Date      : $(date)"
  echo "Total rows: $total_rows"
  echo "=============================================================="
  echo ""
  echo "COLUMN ANALYSIS"
  echo "--------------------------------------------------------------"
  printf "%-22s %6s %8s %8s %10s %10s\n" "Column" "Total" "Empty" "Empty%" "TypeAnom" "Whitespace"
  printf "%-22s %6s %8s %8s %10s %10s\n" "------" "-----" "-----" "------" "--------" "----------"

  awk -F"$delimiter" '
  NR == 1 {
    ncols = NF
    for (i = 1; i <= NF; i++) header[i] = $i
    next
  }
  NF == 0 { next }
  {
    for (i = 1; i <= ncols; i++) {
      total[i]++
      raw = $i
      clean = raw
      gsub(/^[ \t]+|[ \t]+$/, "", clean)
      if (clean == "") {
        empty[i]++
      } else {
        if (clean ~ /^-?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$/) numeric[i]++
        else nonnumeric[i]++
        if (raw != clean) whitespace[i]++
      }
    }
  }
  END {
    for (i = 1; i <= ncols; i++) {
      ep   = (total[i] > 0) ? (empty[i]+0) * 100 / total[i] : 0
      anom = (numeric[i]+0 > nonnumeric[i]+0 && nonnumeric[i]+0 > 0) ? nonnumeric[i] : 0
      printf "%-22s %6d %8d %7.2f%% %10d %10d\n",
        substr(header[i], 1, 22), total[i], empty[i]+0, ep, anom, whitespace[i]+0
    }
  }' "$selected_file"

  echo ""
  echo "DUPLICATE ROWS"
  echo "--------------------------------------------------------------"
  dup_count=$(awk 'NR>1 && NF' "$selected_file" | sort | uniq -d | wc -l)
  echo "Total rows     : $total_rows"
  echo "Duplicate rows : $dup_count"
  if [ "$dup_count" -gt 0 ]; then
    echo ""
    echo "Sample duplicates (up to 5 rows):"
    awk 'NR>1 && NF' "$selected_file" | sort | uniq -d | head -5
  fi

  echo ""
  echo "=============================================================="
} > "$output_file"

whiptail --title "DATA QUALITY REPORT" --scrolltext --msgbox "$(cat "$output_file")" 30 110
