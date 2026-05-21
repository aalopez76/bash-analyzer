#!/bin/bash
# Quick test for SQL export via format.sh
set -uo pipefail

PROJ="/mnt/d/GitHub/Projects/Personal/Bash/bash-analyzer"
cd "$PROJ"

# Pre-seed state
echo "$PROJ" > functions/directory.txt
echo "$PROJ/data.csv" > functions/selected_file.txt

# Mock queue: 
#   0: report msgbox (ack) → any value
#   1: export menu → "2" (SQL INSERTs)
#   2: inputbox table name → "employees"  
#   3: result msgbox (ack) → any value
QUEUE=$(mktemp)
cat > "$QUEUE" << 'QEOF'
ack
2
employees
ack
QEOF

# Setup mock whiptail
MOCK_DIR=$(mktemp -d)
cp tests/mock_whiptail.sh "$MOCK_DIR/whiptail"
chmod +x "$MOCK_DIR/whiptail"

export MOCK_WHIPTAIL_RESPONSES="$QUEUE"
export MOCK_WHIPTAIL_LOG="$PROJ/tests/sql_test.log"
export MOCK_WHIPTAIL_COUNTER="$PROJ/tests/sql_counter.txt"
echo "0" > "$MOCK_WHIPTAIL_COUNTER"
> "$MOCK_WHIPTAIL_LOG"

# Run format.sh with mock
PATH="$MOCK_DIR:$PATH" bash functions/format.sh 2>&1

echo ""
echo "=========================================="
echo "SQL EXPORT TEST RESULTS"
echo "=========================================="

# Find the SQL file
sql_file=$(ls -t output/export_data_*.sql 2>/dev/null | head -1)
if [ -n "$sql_file" ] && [ -f "$sql_file" ]; then
  echo "✔ SQL file created: $sql_file"
  echo ""
  echo "First 5 INSERT statements:"
  head -5 "$sql_file"
  echo ""
  echo "Total INSERTs: $(wc -l < "$sql_file")"
else
  echo "✘ No SQL file found in output/"
  ls -la output/ 2>/dev/null
fi

# Cleanup
rm -f "$QUEUE" "$MOCK_WHIPTAIL_COUNTER"
rm -rf "$MOCK_DIR"
