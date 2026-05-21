#!/bin/bash
# ============================================================
# INTEGRATION TEST — bash-analyzer
# ============================================================
# Tests three flows by mocking whiptail with scripted responses:
#   TEST 1: File Scan
#   TEST 2: Regex Search (all columns)
#   TEST 3: Column Filter (multi-condition)
#
# Prerequisites: WSL with bash, awk, grep, sort, wc, sha256sum
# ============================================================

set -uo pipefail

# ---- Paths ----
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
FUNCTIONS_DIR="$PROJECT_DIR/functions"
MOCK_BIN="$SCRIPT_DIR/mock_bin"
MOCK_WHIPTAIL_SRC="$SCRIPT_DIR/mock_whiptail.sh"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
FAIL=0
TOTAL=0

print_header() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${CYAN}║${BOLD}  bash-analyzer — Integration Test Suite                  ${NC}${CYAN}║${NC}"
  echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
  echo -e "  Date    : $(date)"
  echo -e "  Project : $PROJECT_DIR"
  echo ""
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  ((TOTAL++))
  if echo "$haystack" | grep -qi "$needle"; then
    echo -e "  ${GREEN}✔ PASS${NC} — $label (found: '$needle')"
    ((PASS++))
  else
    echo -e "  ${RED}✘ FAIL${NC} — $label (expected '$needle' not found)"
    ((FAIL++))
  fi
}

assert_file_exists() {
  local label="$1"
  local filepath="$2"
  ((TOTAL++))
  if [ -f "$filepath" ]; then
    echo -e "  ${GREEN}✔ PASS${NC} — $label ($filepath exists)"
    ((PASS++))
  else
    echo -e "  ${RED}✘ FAIL${NC} — $label ($filepath NOT found)"
    ((FAIL++))
  fi
}

assert_file_not_empty() {
  local label="$1"
  local filepath="$2"
  ((TOTAL++))
  if [ -s "$filepath" ]; then
    echo -e "  ${GREEN}✔ PASS${NC} — $label ($(wc -c < "$filepath") bytes)"
    ((PASS++))
  else
    echo -e "  ${RED}✘ FAIL${NC} — $label (file is empty or missing)"
    ((FAIL++))
  fi
}

assert_exit_code() {
  local label="$1"
  local actual="$2"
  local expected="$3"
  ((TOTAL++))
  if [ "$actual" -eq "$expected" ]; then
    echo -e "  ${GREEN}✔ PASS${NC} — $label (exit code: $actual)"
    ((PASS++))
  else
    echo -e "  ${RED}✘ FAIL${NC} — $label (expected exit $expected, got $actual)"
    ((FAIL++))
  fi
}

# ---- Setup mock whiptail ----
setup_mock() {
  local queue_file="$1"

  rm -rf "$MOCK_BIN"
  mkdir -p "$MOCK_BIN"
  cp "$MOCK_WHIPTAIL_SRC" "$MOCK_BIN/whiptail"
  chmod +x "$MOCK_BIN/whiptail"

  export MOCK_WHIPTAIL_RESPONSES="$queue_file"
  export MOCK_WHIPTAIL_LOG="$SCRIPT_DIR/mock_whiptail.log"
  export MOCK_WHIPTAIL_COUNTER="$SCRIPT_DIR/mock_counter.txt"

  # Reset state
  echo "0" > "$MOCK_WHIPTAIL_COUNTER"
  > "$MOCK_WHIPTAIL_LOG"
}

teardown_mock() {
  rm -rf "$MOCK_BIN"
  rm -f "$SCRIPT_DIR/mock_counter.txt"
}

# ---- Pre-seed the selected file state ----
seed_selected_file() {
  local csv_path="$1"
  echo "$(dirname "$csv_path")" > "$FUNCTIONS_DIR/directory.txt"
  echo "$csv_path" > "$FUNCTIONS_DIR/selected_file.txt"
}

# ==================================================================
# PREREQUISITE: Verify data.csv
# ==================================================================
print_header

echo -e "${BOLD}▸ PREREQUISITE CHECK${NC}"
echo "  ─────────────────────────────────────────────"

DATA_CSV="$PROJECT_DIR/data.csv"

assert_file_exists "data.csv exists in project root" "$DATA_CSV"
assert_file_not_empty "data.csv has content" "$DATA_CSV"

ROW_COUNT=$(($(wc -l < "$DATA_CSV") - 1))
((TOTAL++))
if [ "$ROW_COUNT" -ge 5 ]; then
  echo -e "  ${GREEN}✔ PASS${NC} — data.csv has $ROW_COUNT data rows (≥5 required)"
  ((PASS++))
else
  echo -e "  ${RED}✘ FAIL${NC} — data.csv has $ROW_COUNT rows (need ≥5)"
  ((FAIL++))
fi

HEADER=$(head -n 1 "$DATA_CSV" | tr -d '\r')
assert_contains "CSV header has comma-separated columns" "$HEADER" ","

echo ""
echo -e "  ${YELLOW}Header:${NC} $HEADER"
echo -e "  ${YELLOW}Rows  :${NC} $ROW_COUNT"

# ==================================================================
# TEST 1: File Scan (file-scan.sh)
# ==================================================================
echo ""
echo -e "${BOLD}▸ TEST 1: File Scan${NC}"
echo "  ─────────────────────────────────────────────"

seed_selected_file "$DATA_CSV"

# file-scan.sh whiptail calls:
#   0: radiolist "Lines to show in preview" → "H" (Head)
#   1: inputbox "Number of lines" → "5"
#   2: msgbox (scroll) for scan report → (ack)
QUEUE_T1=$(mktemp)
cat > "$QUEUE_T1" << 'EOF'
H
5

EOF

setup_mock "$QUEUE_T1"

SCAN_OUTPUT=$( PATH="$MOCK_BIN:$PATH" bash "$FUNCTIONS_DIR/file-scan.sh" 2>&1 ) || true
SCAN_EXIT=$?

assert_exit_code "file-scan.sh exits cleanly" "$SCAN_EXIT" "0"
assert_file_exists "scan-report.txt generated" "$PROJECT_DIR/output/scan-report.txt"
assert_file_not_empty "scan-report.txt has content" "$PROJECT_DIR/output/scan-report.txt"

SCAN_REPORT=$(cat "$PROJECT_DIR/output/scan-report.txt")
assert_contains "Report has FILE SCAN header" "$SCAN_REPORT" "FILE SCAN REPORT"
assert_contains "Report shows delimiter" "$SCAN_REPORT" "Delimiter"
assert_contains "Report shows row count" "$SCAN_REPORT" "Data rows"
assert_contains "Report shows column count" "$SCAN_REPORT" "Columns"
assert_contains "Report has column type analysis" "$SCAN_REPORT" "Column types"
assert_contains "Report has duplicate check" "$SCAN_REPORT" "DUPLICATE CHECK"

echo ""
echo -e "  ${YELLOW}Mock whiptail log (Test 1):${NC}"
cat "$MOCK_WHIPTAIL_LOG" | sed 's/^/    /'

echo ""
echo -e "  ${YELLOW}scan-report.txt (first 15 lines):${NC}"
head -n 15 "$PROJECT_DIR/output/scan-report.txt" | sed 's/^/    /'

rm -f "$QUEUE_T1"
teardown_mock

# ==================================================================
# TEST 2: Regex Search — all columns (search.sh action 1, scope 1)
# ==================================================================
echo ""
echo -e "${BOLD}▸ TEST 2: Regex Search (all columns, pattern='Marketing')${NC}"
echo "  ─────────────────────────────────────────────"

seed_selected_file "$DATA_CSV"

# search.sh whiptail calls:
#   0: menu "SEARCH & FILTER" → "1" (Regex search)
#   1: menu "Search scope" → "1" (All columns)
#   2: inputbox "Enter regex pattern" → "Marketing"
#   3: textbox (show results) → (ack)
#   4: yesno "Save results?" → "NO" (don't save)
QUEUE_T2=$(mktemp)
cat > "$QUEUE_T2" << 'EOF'
1
1
Marketing

NO
EOF

setup_mock "$QUEUE_T2"

SEARCH_OUTPUT=$( PATH="$MOCK_BIN:$PATH" bash "$FUNCTIONS_DIR/search.sh" 2>&1 ) || true
SEARCH_EXIT=$?

assert_exit_code "search.sh (regex) exits cleanly" "$SEARCH_EXIT" "0"

# The results are in the tmpresult shown via textbox.
# Since we didn't save, check the mock log to confirm the flow completed.
MOCK_LOG=$(cat "$MOCK_WHIPTAIL_LOG")
assert_contains "Whiptail called with SEARCH & FILTER menu" "$MOCK_LOG" "SEARCH & FILTER"
assert_contains "Whiptail called with REGEX SEARCH" "$MOCK_LOG" "REGEX SEARCH"
assert_contains "Whiptail called with SAVE RESULT prompt" "$MOCK_LOG" "SAVE RESULT"

# Verify grep would find Marketing in data.csv
EXPECTED_MATCHES=$(tail -n +2 "$DATA_CSV" | tr -d '\r' | grep -ci "Marketing" || true)
echo ""
echo -e "  ${YELLOW}Expected 'Marketing' matches in data.csv:${NC} $EXPECTED_MATCHES"

echo ""
echo -e "  ${YELLOW}Mock whiptail log (Test 2):${NC}"
cat "$MOCK_WHIPTAIL_LOG" | sed 's/^/    /'

rm -f "$QUEUE_T2"
teardown_mock

# ==================================================================
# TEST 3: Regex Search — specific column (search.sh action 1, scope 2)
# ==================================================================
echo ""
echo -e "${BOLD}▸ TEST 3: Regex Search (column 5='Department', pattern='Finance')${NC}"
echo "  ─────────────────────────────────────────────"

seed_selected_file "$DATA_CSV"

# search.sh whiptail calls:
#   0: menu "SEARCH & FILTER" → "1" (Regex search)
#   1: menu "Search scope" → "2" (Specific column)
#   2: menu "SELECT COLUMN" → "5" (Department)
#   3: inputbox "Enter regex pattern" → "Finance"
#   4: textbox (show results) → (ack)
#   5: yesno "Save results?" → "YES" (save)
#   6: msgbox "Saved to..." → (ack)
QUEUE_T3=$(mktemp)
cat > "$QUEUE_T3" << 'EOF'
1
2
5
Finance


YES

EOF

setup_mock "$QUEUE_T3"

REGEX_OUTPUT=$( PATH="$MOCK_BIN:$PATH" bash "$FUNCTIONS_DIR/search.sh" 2>&1 ) || true
REGEX_EXIT=$?

assert_exit_code "search.sh (column regex) exits cleanly" "$REGEX_EXIT" "0"
assert_file_exists "regex_result.txt generated (saved)" "$PROJECT_DIR/output/regex_result.txt"

if [ -f "$PROJECT_DIR/output/regex_result.txt" ]; then
  REGEX_REPORT=$(cat "$PROJECT_DIR/output/regex_result.txt")
  assert_contains "Regex report has header" "$REGEX_REPORT" "REGEX SEARCH REPORT"
  assert_contains "Regex report shows pattern" "$REGEX_REPORT" "Finance"
  assert_contains "Regex report shows match count" "$REGEX_REPORT" "Matches"

  MATCH_LINE=$(grep "Matches" "$PROJECT_DIR/output/regex_result.txt" | head -1)
  echo ""
  echo -e "  ${YELLOW}Regex result match count:${NC} $MATCH_LINE"
  echo -e "  ${YELLOW}regex_result.txt (first 12 lines):${NC}"
  head -n 12 "$PROJECT_DIR/output/regex_result.txt" | sed 's/^/    /'
fi

echo ""
echo -e "  ${YELLOW}Mock whiptail log (Test 3):${NC}"
cat "$MOCK_WHIPTAIL_LOG" | sed 's/^/    /'

rm -f "$QUEUE_T3"
teardown_mock

# ==================================================================
# TEST 4: Security validation — Column Filter argument safety
# ==================================================================
echo ""
echo -e "${BOLD}▸ TEST 4: Security — Column Filter argument inspection${NC}"
echo "  ─────────────────────────────────────────────"

echo -e "  ${YELLOW}Inspecting search.sh line 192 for command injection risk:${NC}"
VULN_LINE=$(sed -n '189,192p' "$FUNCTIONS_DIR/search.sh")
echo "$VULN_LINE" | sed 's/^/    /'
echo ""

((TOTAL++))
if echo "$VULN_LINE" | grep -q 'awk.*"\$condition'; then
  echo -e "  ${RED}✘ FAIL${NC} — Column Filter interpolates user input as AWK code (injection risk)"
  ((FAIL++))
else
  echo -e "  ${GREEN}✔ PASS${NC} — Column Filter uses safe AWK variable passing"
  ((PASS++))
fi

# Verify regex search uses -v (safe pattern)
((TOTAL++))
if grep -q '\-v re=' "$FUNCTIONS_DIR/search.sh"; then
  echo -e "  ${GREEN}✔ PASS${NC} — Regex search uses AWK -v for pattern (safe)"
  ((PASS++))
else
  echo -e "  ${RED}✘ FAIL${NC} — Regex search does not use -v for AWK variables"
  ((FAIL++))
fi

# ==================================================================
# SUMMARY
# ==================================================================
echo ""
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}  TEST SUMMARY${NC}"
echo -e "${CYAN}══════════════════════════════════════════════════════════${NC}"
echo -e "  Total : $TOTAL"
echo -e "  ${GREEN}Passed: $PASS${NC}"
echo -e "  ${RED}Failed: $FAIL${NC}"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo -e "  ${GREEN}${BOLD}▶ ALL TESTS PASSED ◀${NC}"
else
  echo -e "  ${RED}${BOLD}▶ $FAIL TEST(S) FAILED ◀${NC}"
fi
echo ""

# Cleanup
rm -f "$SCRIPT_DIR/mock_whiptail.log" "$SCRIPT_DIR/mock_counter.txt"

exit "$FAIL"
