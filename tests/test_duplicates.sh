#!/bin/bash
# Test: File Scan duplicate detection with data.csv and data_1.csv
set -uo pipefail

PROJ="/mnt/d/GitHub/Projects/Personal/Bash/bash-analyzer"
cd "$PROJ"

echo "=== DUPLICATE DETECTION TEST ==="
echo ""

# Pre-seed: select data.csv (which lives in the project root alongside data_1.csv)
echo "$PROJ" > functions/directory.txt
echo "$PROJ/data.csv" > functions/selected_file.txt

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
else
  echo "✘ FAIL — data_1.csv NOT detected as duplicate"
  echo ""
  echo "Full report:"
  cat output/scan-report.txt
fi

# Cleanup
rm -f "$QUEUE" "$PROJ/tests/dup_counter.txt" "$PROJ/tests/dup_test.log"
rm -rf "$MOCK_DIR"
