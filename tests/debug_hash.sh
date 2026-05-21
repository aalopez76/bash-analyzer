#!/bin/bash
cd /mnt/d/GitHub/Projects/Personal/Bash/bash-analyzer

echo "=== HASH COMPARISON ==="
echo "--- Hash of ORIGINAL data.csv (with CRLF) ---"
sha256sum data.csv

echo "--- Hash of NORMALIZED data.csv (after tr -d \\r) ---"
tr -d '\r' < data.csv | sha256sum

echo ""
ORIG=$(sha256sum data.csv | awk '{print $1}')
NORM=$(tr -d '\r' < data.csv | sha256sum | awk '{print $1}')
echo "Original hash : $ORIG"
echo "Normalized hash: $NORM"

if [ "$ORIG" = "$NORM" ]; then
  echo "Result: SAME (no CRLF issue)"
else
  echo "Result: DIFFERENT — normalized file has different hash than original!"
fi

echo ""
echo "=== SIMULATING file-scan.sh DUPLICATE CHECK ==="
echo "selected_file points to normalized temp copy in /tmp"
echo "other files are compared from ORIGINAL directory"
echo ""

# Simulate what file-scan.sh does:
# selected_file = normalized copy (/tmp)
# original_hash = sha256sum of normalized copy
# other_file hashes = sha256sum of originals in directory

normalized_hash="$NORM"
echo "Hash of selected (normalized): $normalized_hash"

for f in data.csv data_1.csv; do
  h=$(sha256sum "$f" | awk '{print $1}')
  echo "Hash of $f (original):         $h"
  if [ "$normalized_hash" = "$h" ]; then
    echo "  → MATCH"
  else
    echo "  → NO MATCH (CRLF causes different hash!)"
  fi
done
