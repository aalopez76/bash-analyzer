#!/bin/bash
# ============================================================
# TEST — CSV quoting-aware parsing (M6)
# ============================================================
# Two layers:
#   A) Unit-test the shared helper (common.sh:csv_fpat / AWK_UNQUOTE):
#      a quoted field containing the delimiter must count as ONE field,
#      while the naive -F split miscounts it (negative control).
#   B) Integration: file-scan.sh (the pilot module) routed through the
#      helper must classify the column AFTER a quoted, comma-bearing
#      field as NUMERIC — naive splitting would shift fields and wrongly
#      tag it NON-NUMERIC.
#
# Fixture quoted.csv:
#   name,score
#   "Smith, John",100   <- embedded comma inside a quoted field
#   "Doe, Jane",200
#   Plain,300
# ============================================================
set -uo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$TEST_DIR")"
FIX="$TEST_DIR/fixtures"
cd "$PROJ" || exit 1

PASS=0; FAIL=0
ok()  { echo "  ✔ PASS — $1"; ((PASS++)); }
bad() { echo "  ✘ FAIL — $1"; ((FAIL++)); }

echo "=== CSV QUOTING TEST (M6) ==="

# ---- A. Helper unit test ----
# shellcheck source=functions/common.sh
source functions/common.sh >/dev/null 2>&1

fpat=$(csv_fpat ",")

nf_aware=$(awk -v FPAT="$fpat" 'NR==2 {print NF}' "$FIX/quoted.csv")
if [ "$nf_aware" = "2" ]; then
  ok "quoting-aware split counts 2 fields (embedded comma respected)"
else
  bad "expected NF=2 with csv_fpat, got NF=$nf_aware"
fi

# Negative control: the naive split is supposed to be wrong (proves the bug
# the helper fixes really exists). If this ever yields 2, the fixture lost its
# embedded delimiter and the test is no longer meaningful.
nf_naive=$(awk -F"," 'NR==2 {print NF}' "$FIX/quoted.csv")
if [ "$nf_naive" = "3" ]; then
  ok "naive -F split miscounts (NF=3) — confirms the bug being fixed"
else
  bad "expected naive NF=3, got NF=$nf_naive (fixture may be wrong)"
fi

# Unquote helper: surrounding quotes stripped, "" unescaped.
val=$(awk -v FPAT="$fpat" "$AWK_UNQUOTE"'NR==2 {print unq($1)}' "$FIX/quoted.csv")
if [ "$val" = "Smith, John" ]; then
  ok "unq() strips surrounding quotes (got: $val)"
else
  bad "unq() wrong, got: [$val]"
fi

# ---- B. file-scan.sh integration ----
MOCK_DIR=$(mktemp -d)
cp "$TEST_DIR/mock_whiptail.sh" "$MOCK_DIR/whiptail"
chmod +x "$MOCK_DIR/whiptail"
QUEUE=$(mktemp)
export MOCK_WHIPTAIL_RESPONSES="$QUEUE"
export MOCK_WHIPTAIL_LOG="$TEST_DIR/quoting_test.log"
export MOCK_WHIPTAIL_COUNTER="$TEST_DIR/quoting_counter.txt"
trap 'rm -rf "$MOCK_DIR" "$QUEUE" "$MOCK_WHIPTAIL_LOG" "$MOCK_WHIPTAIL_COUNTER"' EXIT

echo "$FIX" > functions/directory.txt
echo "$FIX/quoted.csv" > functions/selected_file.txt
echo "0" > "$MOCK_WHIPTAIL_COUNTER"
: > "$MOCK_WHIPTAIL_LOG"
# file-scan whiptail calls: 1) lines radiolist → "N" (skip preview),
# 2) final report msgbox → ack
printf 'N\nack\n' > "$QUEUE"

PATH="$MOCK_DIR:$PATH" bash functions/file-scan.sh >/dev/null 2>&1

REPORT="output/scan-report.txt"
if [ ! -f "$REPORT" ]; then
  bad "scan-report.txt generated"
  echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
  exit 1
fi
ok "scan-report.txt generated"
C=$(cat "$REPORT")

if echo "$C" | grep -q "Columns   : 2"; then
  ok "reports 2 columns"
else
  bad "column count wrong (expected 2)"
fi

# The discriminator: with quoting-aware splitting, 'score' (column after the
# quoted comma-bearing field) is NUMERIC. Naive splitting would tag it
# NON-NUMERIC because ' John\"' would land in the score column.
if echo "$C" | grep -Eq "Column 2 \(score\): NUMERIC"; then
  ok "score column classified NUMERIC (quoting-aware)"
else
  bad "score not NUMERIC — quoting not honoured"
  echo "$C" | grep -i "Column" | sed 's/^/      /'
fi

if echo "$C" | grep -Eq "Column 1 \(name\): NON-NUMERIC"; then
  ok "name column classified NON-NUMERIC"
else
  bad "name classification wrong"
fi

echo ""
echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
