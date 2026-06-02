#!/bin/bash
# ============================================================
# TEST — CSV Joiner (functions/csv-joiner.sh)
# ============================================================
# Covers INNER and LEFT joins between two fixtures keyed on DeptID.
# Drives the secondary-file picker and all menus via the whiptail mock.
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$SCRIPT_DIR")"
FIX="$SCRIPT_DIR/fixtures"
cd "$PROJ"

PASS=0; FAIL=0
ok()   { echo "  ✔ PASS — $1"; ((PASS++)); }
bad()  { echo "  ✘ FAIL — $1"; ((FAIL++)); }
check(){ if echo "$2" | grep -q "$3"; then ok "$1"; else bad "$1 (missing: $3)"; fi; }

MOCK_DIR=$(mktemp -d)
cp "$SCRIPT_DIR/mock_whiptail.sh" "$MOCK_DIR/whiptail"
chmod +x "$MOCK_DIR/whiptail"
QUEUE=$(mktemp)
export MOCK_WHIPTAIL_RESPONSES="$QUEUE"
export MOCK_WHIPTAIL_LOG="$SCRIPT_DIR/joiner_test.log"
export MOCK_WHIPTAIL_COUNTER="$SCRIPT_DIR/joiner_counter.txt"
trap 'rm -rf "$MOCK_DIR" "$QUEUE" "$MOCK_WHIPTAIL_LOG" "$MOCK_WHIPTAIL_COUNTER"' EXIT

run_join() {
  # $1 = join type label for the queue (INNER/LEFT/...)
  echo "0" > "$MOCK_WHIPTAIL_COUNTER"
  : > "$MOCK_WHIPTAIL_LOG"
  # Pre-seed state: primary file + working directory (where the picker looks)
  echo "$FIX" > functions/directory.txt
  echo "$FIX/employees.csv" > functions/selected_file.txt
  # Queue, in call order:
  #   navigate_and_select menu  → "departments.csv"  (secondary file)
  #   JOIN TYPE menu            → "$1"
  #   PRIMARY KEY menu          → "3"  (DeptID in employees.csv)
  #   SECONDARY KEY menu        → "1"  (DeptID in departments.csv)
  #   JOIN RESULT scrolltext    → ack
  #   saved msgbox              → ack
  #   ANALYZE post-menu         → "4"  (Done)
  cat > "$QUEUE" <<EOF
departments.csv
$1
3
1
ack
ack
4
EOF
  PATH="$MOCK_DIR:$PATH" bash functions/csv-joiner.sh >/dev/null 2>&1
}

echo "=== CSV JOINER TEST ==="

# ---------- INNER JOIN ----------
echo ""
echo "▸ INNER JOIN (employees.DeptID = departments.DeptID)"
run_join "INNER"
CSV="output/join_result.csv"
if [ ! -f "$CSV" ]; then
  bad "join_result.csv generated"
else
  ok "join_result.csv generated"
  CONTENT=$(cat "$CSV")
  # Header: primary columns + secondary columns minus the secondary key
  check "header has combined columns" "$CONTENT" "EmpID,Name,DeptID,DeptName"
  # Secondary key column must NOT be duplicated
  HEADER=$(head -n1 "$CSV")
  dept_count=$(awk -F, '{ n=0; for(i=1;i<=NF;i++) if($i=="DeptID") n++; print n }' <<<"$HEADER")
  if [ "$dept_count" -eq 1 ]; then ok "secondary key excluded (DeptID appears once)"; else bad "DeptID appears $dept_count times (expected 1)"; fi
  # INNER: 3 matching rows (Alice/Carol→Engineering, Bob→Sales); Dave(99) dropped
  rows=$(($(wc -l < "$CSV") - 1))
  if [ "$rows" -eq 3 ]; then ok "INNER yields 3 rows"; else bad "INNER rows=$rows (expected 3)"; fi
  check "INNER maps Alice to Engineering" "$CONTENT" "Alice,10,Engineering"
  if grep -q "Dave" "$CSV"; then bad "Dave(99) wrongly included in INNER"; else ok "Dave(99) correctly excluded from INNER"; fi
fi

# ---------- LEFT JOIN ----------
echo ""
echo "▸ LEFT JOIN (all employees, matched or not)"
run_join "LEFT"
if [ -f "$CSV" ]; then
  rows=$(($(wc -l < "$CSV") - 1))
  # LEFT: all 4 employees (Dave with empty DeptName)
  if [ "$rows" -eq 4 ]; then ok "LEFT yields 4 rows"; else bad "LEFT rows=$rows (expected 4)"; fi
  if grep -q "Dave,99," "$CSV"; then ok "LEFT keeps Dave(99) with empty department"; else bad "LEFT lost Dave(99)"; fi
fi

echo ""
echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
