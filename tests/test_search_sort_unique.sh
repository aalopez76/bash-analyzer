#!/bin/bash
# ============================================================
# TEST — Search & Filter: Sort and Unique (functions/search.sh)
# ============================================================
# Covers action 3 (numeric-aware sort) and action 4 (unique values)
# using employees.csv. Regex and column-filter are covered by
# integration_test.sh.
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
export MOCK_WHIPTAIL_LOG="$SCRIPT_DIR/ssu_test.log"
export MOCK_WHIPTAIL_COUNTER="$SCRIPT_DIR/ssu_counter.txt"
trap 'rm -rf "$MOCK_DIR" "$QUEUE" "$MOCK_WHIPTAIL_LOG" "$MOCK_WHIPTAIL_COUNTER"' EXIT

seed() {
  echo "$FIX" > functions/directory.txt
  echo "$FIX/employees.csv" > functions/selected_file.txt
  echo "0" > "$MOCK_WHIPTAIL_COUNTER"
  : > "$MOCK_WHIPTAIL_LOG"
}
run() { PATH="$MOCK_DIR:$PATH" bash functions/search.sh >/dev/null 2>&1; }

echo "=== SEARCH SORT & UNIQUE TEST ==="

# ---------- Sort by DeptID (numeric, col 3) ----------
# Call order: ACTION menu "3" / SELECT COLUMN "3" / add-column yesno "NO"
#             / save textbox ack / save yesno "Save" / saved msgbox ack
echo ""
echo "▸ Sort by DeptID (numeric ascending)"
seed
printf '3\n3\nNO\nack\nSave\nack\n' > "$QUEUE"
run
SORT="output/sort_result.txt"
if [ -f "$SORT" ]; then
  ok "sort_result.txt generated"
  if grep -q "Records   : 4" "$SORT"; then ok "sort reports 4 records"; else bad "sort record count wrong"; fi
  # Data section is everything after the blank line following the header row.
  # Numeric sort on 10,20,99 must place Dave (99) last, after Bob (20).
  bob_ln=$(grep -n "^2,Bob,20" "$SORT" | head -1 | cut -d: -f1)
  dave_ln=$(grep -n "^4,Dave,99" "$SORT" | head -1 | cut -d: -f1)
  if [ -n "$bob_ln" ] && [ -n "$dave_ln" ] && [ "$dave_ln" -gt "$bob_ln" ]; then
    ok "numeric sort: Dave(99) after Bob(20)"
  else
    bad "numeric sort order wrong (bob_ln=$bob_ln dave_ln=$dave_ln)"
  fi
else
  bad "sort_result.txt generated"
fi

# ---------- Unique values of DeptID (col 3) ----------
# Call order: ACTION menu "4" / SELECT COLUMN "3"
#             / save textbox ack / save yesno "Save" / saved msgbox ack
echo ""
echo "▸ Unique values of DeptID"
seed
printf '4\n3\nack\nSave\nack\n' > "$QUEUE"
run
UNIQ="output/unique_result.txt"
if [ -f "$UNIQ" ]; then
  ok "unique_result.txt generated"
  # DeptID values are 10,20,10,99 → 3 distinct
  if grep -q "Unique values: 3" "$UNIQ"; then ok "reports 3 unique DeptID values"; else bad "unique count wrong"; fi
  for v in 10 20 99; do
    if grep -qx "$v" "$UNIQ"; then ok "unique list contains $v"; else bad "unique list missing $v"; fi
  done
else
  bad "unique_result.txt generated"
fi

echo ""
echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
