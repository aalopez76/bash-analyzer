#!/bin/bash
# ============================================================
# TEST — Format & Export (functions/format.sh)
# ============================================================
# Covers Clean CSV (null fill + malformed-row removal), JSON and
# Markdown exports using malformed.csv. SQL export is covered by
# test_sql_export.sh.
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$SCRIPT_DIR")"
FIX="$SCRIPT_DIR/fixtures"
cd "$PROJ" || exit 1

PASS=0; FAIL=0
ok()  { echo "  ✔ PASS — $1"; ((PASS++)); }
bad() { echo "  ✘ FAIL — $1"; ((FAIL++)); }

MOCK_DIR=$(mktemp -d)
cp "$SCRIPT_DIR/mock_whiptail.sh" "$MOCK_DIR/whiptail"
chmod +x "$MOCK_DIR/whiptail"
QUEUE=$(mktemp)
export MOCK_WHIPTAIL_RESPONSES="$QUEUE"
export MOCK_WHIPTAIL_LOG="$SCRIPT_DIR/fmt_test.log"
export MOCK_WHIPTAIL_COUNTER="$SCRIPT_DIR/fmt_counter.txt"
trap 'rm -rf "$MOCK_DIR" "$QUEUE" "$MOCK_WHIPTAIL_LOG" "$MOCK_WHIPTAIL_COUNTER"' EXIT

seed() {
  echo "$FIX" > functions/directory.txt
  echo "$FIX/malformed.csv" > functions/selected_file.txt
  echo "0" > "$MOCK_WHIPTAIL_COUNTER"
  : > "$MOCK_WHIPTAIL_LOG"
}
run() { PATH="$MOCK_DIR:$PATH" bash functions/format.sh >/dev/null 2>&1; }

echo "=== FORMAT & EXPORT TEST ==="

# ---------- Clean CSV ----------
# Queue: report ack / export menu "1" / fill value "NULLED" / complete ack
echo ""
echo "▸ Clean CSV (fill nulls=NULLED, drop malformed rows)"
seed
printf 'ack\n1\nNULLED\nack\n' > "$QUEUE"
run
CLEAN="output/clean_result.csv"
if [ -f "$CLEAN" ]; then
  ok "clean_result.csv generated"
  # malformed.csv: rows 1,2,3 / 4,,6 / 7,8 / 9,10,11
  # '7,8' has 2 cols → dropped; empty field in '4,,6' → filled
  rows=$(($(wc -l < "$CLEAN") - 1))
  if [ "$rows" -eq 3 ]; then ok "Clean CSV keeps 3 well-formed rows (drops short row)"; else bad "clean rows=$rows (expected 3)"; fi
  if grep -q "4,NULLED,6" "$CLEAN"; then ok "empty field filled with NULLED"; else bad "null fill not applied"; fi
  if grep -q "^7,8$" "$CLEAN"; then bad "malformed row '7,8' not removed"; else ok "malformed row '7,8' removed"; fi
else
  bad "clean_result.csv generated"
fi

# ---------- JSON ----------
# Queue: report ack / export menu "3" / complete ack
echo ""
echo "▸ JSON array export"
seed
printf 'ack\n3\nack\n' > "$QUEUE"
run
# Test-controlled filenames (no spaces/newlines); ls -t is fine here.
# shellcheck disable=SC2012
JSON=$(ls -t output/export_malformed_*.json 2>/dev/null | head -1)
if [ -n "$JSON" ] && [ -f "$JSON" ]; then
  ok "JSON file generated"
  C=$(cat "$JSON")
  if echo "$C" | grep -q '^\[' && echo "$C" | grep -q '^\]'; then ok "JSON is a bracketed array"; else bad "JSON missing array brackets"; fi
  if echo "$C" | grep -q '"a": 1'; then ok "JSON emits numeric value unquoted"; else bad "numeric value not emitted as expected"; fi
  if echo "$C" | grep -q '"b": null'; then ok "JSON emits null for empty field"; else bad "null not emitted for empty field"; fi
else
  bad "JSON file generated"
fi

# ---------- Markdown ----------
# Queue: report ack / export menu "4" / complete ack
echo ""
echo "▸ Markdown table export"
seed
printf 'ack\n4\nack\n' > "$QUEUE"
run
# Test-controlled filenames (no spaces/newlines); ls -t is fine here.
# shellcheck disable=SC2012
MD=$(ls -t output/export_malformed_*.md 2>/dev/null | head -1)
if [ -n "$MD" ] && [ -f "$MD" ]; then
  ok "Markdown file generated"
  C=$(cat "$MD")
  if echo "$C" | grep -q '| a | b | c |'; then ok "Markdown header row present"; else bad "Markdown header row missing"; fi
  if echo "$C" | grep -q '| --- |'; then ok "Markdown separator row present"; else bad "Markdown separator missing"; fi
else
  bad "Markdown file generated"
fi

echo ""
echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
