#!/bin/bash
# ============================================================
# TEST — Data Quality (functions/data-quality.sh)
# ============================================================
# Uses quality.csv (one empty age, one type anomaly, one whitespace
# value, one duplicate row) and asserts the report reflects them.
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$SCRIPT_DIR")"
FIX="$SCRIPT_DIR/fixtures"
cd "$PROJ"

PASS=0; FAIL=0
ok()  { echo "  ✔ PASS — $1"; ((PASS++)); }
bad() { echo "  ✘ FAIL — $1"; ((FAIL++)); }

MOCK_DIR=$(mktemp -d)
cp "$SCRIPT_DIR/mock_whiptail.sh" "$MOCK_DIR/whiptail"
chmod +x "$MOCK_DIR/whiptail"
QUEUE=$(mktemp)
export MOCK_WHIPTAIL_RESPONSES="$QUEUE"
export MOCK_WHIPTAIL_LOG="$SCRIPT_DIR/dq_test.log"
export MOCK_WHIPTAIL_COUNTER="$SCRIPT_DIR/dq_counter.txt"
trap 'rm -rf "$MOCK_DIR" "$QUEUE" "$MOCK_WHIPTAIL_LOG" "$MOCK_WHIPTAIL_COUNTER"' EXIT

echo "$FIX" > functions/directory.txt
echo "$FIX/quality.csv" > functions/selected_file.txt
echo "0" > "$MOCK_WHIPTAIL_COUNTER"
: > "$MOCK_WHIPTAIL_LOG"
# Only one whiptail call: the final report msgbox → ack
printf 'ack\n' > "$QUEUE"

echo "=== DATA QUALITY TEST ==="
PATH="$MOCK_DIR:$PATH" bash functions/data-quality.sh >/dev/null 2>&1

REPORT="output/quality-report.txt"
if [ ! -f "$REPORT" ]; then
  bad "quality-report.txt generated"
  echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
  exit 1
fi
ok "quality-report.txt generated"
C=$(cat "$REPORT")

# 6 data rows (blank lines excluded; the duplicate row counts as a row)
if echo "$C" | grep -q "Total rows: 6"; then ok "counts 6 data rows"; else bad "row count wrong"; fi

# age column: 1 empty value (row 2)
age_line=$(echo "$C" | awk '/^age/ {print; exit}')
empty_in_age=$(echo "$age_line" | awk '{print $3}')
if [ "$empty_in_age" = "1" ]; then ok "age has 1 empty value"; else bad "age empty=$empty_in_age (expected 1)"; fi

# age column: 1 type anomaly ('abc' among numerics)
anom_in_age=$(echo "$age_line" | awk '{print $5}')
if [ "$anom_in_age" = "1" ]; then ok "age has 1 type anomaly"; else bad "age anomaly=$anom_in_age (expected 1)"; fi

# age column: 1 whitespace value (' 40 ')
ws_in_age=$(echo "$age_line" | awk '{print $6}')
if [ "$ws_in_age" = "1" ]; then ok "age has 1 whitespace value"; else bad "age whitespace=$ws_in_age (expected 1)"; fi

# duplicate rows: the '3,25,NYC' row appears twice → 1 duplicate group
if echo "$C" | grep -q "Duplicate rows : 1"; then ok "detects 1 duplicate row"; else bad "duplicate count wrong"; fi

echo ""
echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
