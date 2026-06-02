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

# ---- C. data-quality.sh integration (reuses quoted.csv) ----
# selected_file already points at quoted.csv; reset the mock for one msgbox.
echo "0" > "$MOCK_WHIPTAIL_COUNTER"
: > "$MOCK_WHIPTAIL_LOG"
printf 'ack\n' > "$QUEUE"

PATH="$MOCK_DIR:$PATH" bash functions/data-quality.sh >/dev/null 2>&1

DQ="output/quality-report.txt"
if [ ! -f "$DQ" ]; then
  bad "quality-report.txt generated"
  echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
  exit 1
fi
ok "quality-report.txt generated"
Q=$(cat "$DQ")

if echo "$Q" | grep -q "Total rows: 3"; then
  ok "data-quality counts 3 rows"
else
  bad "data-quality row count wrong (expected 3)"
fi

# Discriminator: the 'score' column report line. Columns printed are
# name Total Empty Empty% TypeAnom Whitespace → $6 is the Whitespace count.
# With quoting-aware splitting score = 100/200/300 → 0 whitespace. Naive
# splitting would drop ' John"'/' Jane"' (leading space) into the score
# column → whitespace=2.
score_line=$(echo "$Q" | awk '/^score/ {print; exit}')
score_ws=$(echo "$score_line" | awk '{print $6}')
if [ "$score_ws" = "0" ]; then
  ok "score column has 0 whitespace values (quoting-aware)"
else
  bad "score whitespace=$score_ws (expected 0) — quoting not honoured"
  echo "      $score_line"
fi

# And the empty count for score must be 0 (no shifted/blank fields).
score_empty=$(echo "$score_line" | awk '{print $3}')
if [ "$score_empty" = "0" ]; then
  ok "score column has 0 empty values"
else
  bad "score empty=$score_empty (expected 0)"
fi

# ---- D. search.sh column filter integration (reuses quoted.csv) ----
# Filter: score (col 2) > 150 → Doe(200) + Plain(300) = 2 records.
# Naive splitting would put ' Jane"' in the score column for the Doe row
# (numeric value 0), wrongly excluding it and reporting only 1 record.
# Call order: ACTION "2" / SELECT COLUMN "2" / OPERATOR ">" / value "150"
#             / SELECT COLUMN "none" (done) / save textbox ack
#             / save yesno "Save" / saved msgbox ack
echo "0" > "$MOCK_WHIPTAIL_COUNTER"
: > "$MOCK_WHIPTAIL_LOG"
printf '2\n2\n>\n150\nnone\nack\nSave\nack\n' > "$QUEUE"

PATH="$MOCK_DIR:$PATH" bash functions/search.sh >/dev/null 2>&1

CF="output/condition_result.txt"
if [ ! -f "$CF" ]; then
  bad "condition_result.txt generated"
  echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
  exit 1
fi
ok "condition_result.txt generated"
F=$(cat "$CF")

if echo "$F" | grep -q "Records    : 2"; then
  ok "column filter score>150 returns 2 records (quoting-aware)"
else
  bad "filter record count wrong (expected 2) — quoting not honoured"
  echo "$F" | grep -i "Records" | sed 's/^/      /'
fi

# Doe (200) must survive the filter; naive splitting would drop it.
if echo "$F" | grep -q "Doe, Jane"; then
  ok "filtered output keeps the quoted, comma-bearing row (Doe, Jane / 200)"
else
  bad "Doe row missing from filtered output"
fi

# ---- E. search.sh unique values integration (reuses quoted.csv) ----
# Unique on name (col 1): the quoted values keep their embedded comma intact.
# Call order: ACTION "4" / SELECT COLUMN "1" / save textbox ack
#             / save yesno "Save" / saved msgbox ack
echo "0" > "$MOCK_WHIPTAIL_COUNTER"
: > "$MOCK_WHIPTAIL_LOG"
printf '4\n1\nack\nSave\nack\n' > "$QUEUE"

PATH="$MOCK_DIR:$PATH" bash functions/search.sh >/dev/null 2>&1

UQ="output/unique_result.txt"
if [ ! -f "$UQ" ]; then
  bad "unique_result.txt generated"
  echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
  exit 1
fi
ok "unique_result.txt generated"
U=$(cat "$UQ")

# 3 distinct names; "Smith, John" must appear as ONE unquoted value with its
# comma preserved (naive splitting would shatter it into "Smith / John").
if echo "$U" | grep -q "Unique values: 3"; then
  ok "unique reports 3 distinct names"
else
  bad "unique count wrong (expected 3)"
fi
if echo "$U" | grep -qx "Smith, John"; then
  ok "unique value 'Smith, John' kept intact (quoting-aware)"
else
  bad "'Smith, John' not preserved as a single unique value"
fi

# ---- F. format.sh integrity + JSON export (reuses quoted.csv) ----
# With quoting-aware NF every row has 2 columns → no malformed rows. Naive
# splitting would see 3 columns in the quoted rows and flag them malformed.
# Then export JSON and confirm the comma-bearing name survives as one value.
# Call order: report msgbox ack / export menu "3" (JSON) / complete msgbox ack
echo "0" > "$MOCK_WHIPTAIL_COUNTER"
: > "$MOCK_WHIPTAIL_LOG"
printf 'ack\n3\nack\n' > "$QUEUE"

PATH="$MOCK_DIR:$PATH" bash functions/format.sh >/dev/null 2>&1

FR="output/format-report.txt"
if [ -f "$FR" ] && grep -q "All rows have correct column count" "$FR"; then
  ok "format integrity: no malformed rows (quoting-aware NF)"
else
  bad "format flagged malformed rows — quoting not honoured"
  [ -f "$FR" ] && grep -i "malformed\|correct column" "$FR" | sed 's/^/      /'
fi

# Test-controlled filename (no spaces/newlines); ls -t is fine here.
# shellcheck disable=SC2012
JSONF=$(ls -t output/export_quoted_*.json 2>/dev/null | head -1)
if [ -n "$JSONF" ] && grep -q '"name": "Smith, John"' "$JSONF"; then
  ok "JSON export keeps comma-bearing value as one field (quoting-aware)"
else
  bad "JSON export split the quoted value"
  [ -n "$JSONF" ] && grep -i "smith" "$JSONF" | sed 's/^/      /'
fi

# ---- G. csv-joiner.sh with a quoted, comma-bearing JOIN KEY ----
# Primary qjoin_left.csv keyed on dept (col 2 = "North, East"); secondary
# qjoin_right.csv keyed on region (col 1 = "North, East"). The keys only match
# if the embedded comma is honoured (patsplit + unq); naive splitting shatters
# the key and the joined columns. Selected file is re-seeded to the primary.
echo "$FIX" > functions/directory.txt
echo "$FIX/qjoin_left.csv" > functions/selected_file.txt
echo "0" > "$MOCK_WHIPTAIL_COUNTER"
: > "$MOCK_WHIPTAIL_LOG"
# Call order: secondary picker → "qjoin_right.csv" / JOIN TYPE "INNER"
#   / PRIMARY KEY "2" (dept) / SECONDARY KEY "1" (region)
#   / result scrolltext ack / saved msgbox ack / post-menu "4" (Done)
cat > "$QUEUE" <<'EOF'
qjoin_right.csv
INNER
2
1
ack
ack
4
EOF

PATH="$MOCK_DIR:$PATH" bash functions/csv-joiner.sh >/dev/null 2>&1

JC="output/join_result.csv"
if [ ! -f "$JC" ]; then
  bad "join_result.csv generated"
  echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
  exit 1
fi
ok "join_result.csv generated"
J=$(cat "$JC")

# Combined header excludes the secondary key (region): emp,dept,manager
if echo "$J" | head -1 | grep -qx "emp,dept,manager"; then
  ok "join header excludes secondary key (emp,dept,manager)"
else
  bad "join header wrong: $(echo "$J" | head -1)"
fi

# INNER on the quoted key yields 2 matched rows.
jrows=$(($(wc -l < "$JC") - 1))
if [ "$jrows" -eq 2 ]; then
  ok "INNER on quoted key yields 2 rows (quoting-aware)"
else
  bad "join rows=$jrows (expected 2) — quoted key not matched"
fi

# The decisive row: Alice keeps her quoted dept AND is joined to the right
# manager. Naive splitting cannot produce this exact line.
if echo "$J" | grep -qx 'Alice,"North, East",Smith'; then
  ok "quoted key matched correctly (Alice → North, East → Smith)"
else
  bad "quoted-key join row wrong"
  # sed indents each line of the diagnostic dump; sed is clearest here.
  # shellcheck disable=SC2001
  echo "$J" | sed 's/^/      /'
fi

echo ""
echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
