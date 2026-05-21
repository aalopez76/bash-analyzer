#!/bin/bash
# Test: File Scan duplicate detection.
# Creates a temp directory with two identical CSVs (data.csv + data_1.csv)
# and verifies file-scan.sh detects them as duplicates by hash.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$SCRIPT_DIR")"
cd "$PROJ"

SOURCE_CSV="$PROJ/data_sets/data.csv"
if [ ! -f "$SOURCE_CSV" ]; then
  echo "✘ FAIL — source dataset not found at $SOURCE_CSV"
  exit 1
fi

echo "=== DUPLICATE DETECTION TEST ==="
echo ""

# Stage two identical CSVs in an isolated temp directory so file-scan.sh
# can find a duplicate without polluting the repo.
STAGE_DIR=$(mktemp -d)
trap 'rm -rf "$STAGE_DIR" "$QUEUE" "$MOCK_DIR" "$PROJ/tests/dup_counter.txt" "$PROJ/tests/dup_test.log"' EXIT

cp "$SOURCE_CSV" "$STAGE_DIR/data.csv"
cp "$SOURCE_CSV" "$STAGE_DIR/data_1.csv"

echo "$STAGE_DIR" > functions/directory.txt
echo "$STAGE_DIR/data.csv" > functions/selected_file.txt

# Mock queue for file-scan.sh:
#   0: radiolist "preview" → "H"
#   1: inputbox "num lines" → "3"
#   2: msgbox (report) → ack
QUEUE=$(mktemp)
cat > "$QUEUE" << 'EOF'
H
3
ack
EOF

MOCK_DIR=$(mktemp -d)
cp tests/mock_whiptail.sh "$MOCK_DIR/whiptail"
chmod +x "$MOCK_DIR/whiptail"

export MOCK_WHIPTAIL_RESPONSES="$QUEUE"
export MOCK_WHIPTAIL_LOG="$PROJ/tests/dup_test.log"
export MOCK_WHIPTAIL_COUNTER="$PROJ/tests/dup_counter.txt"
echo "0" > "$MOCK_WHIPTAIL_COUNTER"
> "$MOCK_WHIPTAIL_LOG"

PATH="$MOCK_DIR:$PATH" bash functions/file-scan.sh 2>&1

echo ""
echo "=== SCAN REPORT — DUPLICATE SECTION ==="
grep -A 10 "DUPLICATE CHECK" output/scan-report.txt

echo ""
if grep -q "data_1.csv" output/scan-report.txt; then
  echo "✔ PASS — data_1.csv detected as duplicate of data.csv"
  exit 0
else
  echo "✘ FAIL — data_1.csv NOT detected as duplicate"
  echo ""
  echo "Full report:"
  cat output/scan-report.txt
  exit 1
fi
