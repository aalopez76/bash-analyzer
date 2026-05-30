#!/bin/bash
# ============================================================
# AGGREGATE TEST RUNNER — bash-analyzer
# ============================================================
# Runs every test script in the suite and reports an aggregate
# pass/fail. Consumed by `make test` and by CI.
#
# A test script is considered PASSED when it exits 0.
# Prerequisites: bash, awk, grep, sort, wc, sha256sum
# (whiptail is NOT required — tests use the mock in tests/).
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# Test scripts to run, in order.
TESTS=(
  "integration_test.sh"
  "test_duplicates.sh"
  "test_sql_export.sh"
  "test_joiner.sh"
  "test_data_quality.sh"
  "test_format.sh"
  "test_search_sort_unique.sh"
)

passed=0
failed=0
failed_names=()

echo -e "${CYAN}${BOLD}Running bash-analyzer test suite${NC}"
echo "================================================"

for t in "${TESTS[@]}"; do
  path="$SCRIPT_DIR/$t"
  if [ ! -f "$path" ]; then
    echo -e "${RED}MISSING${NC} $t"
    ((failed++)); failed_names+=("$t (missing)")
    continue
  fi
  echo ""
  echo -e "${BOLD}▶ $t${NC}"
  echo "------------------------------------------------"
  if bash "$path"; then
    echo -e "${GREEN}✔ $t passed${NC}"
    ((passed++))
  else
    echo -e "${RED}✘ $t failed${NC}"
    ((failed++)); failed_names+=("$t")
  fi
done

echo ""
echo "================================================"
echo -e "${BOLD}AGGREGATE RESULT${NC}  passed=$passed  failed=$failed"
if [ "$failed" -ne 0 ]; then
  printf '  %s\n' "${failed_names[@]}"
  echo -e "${RED}${BOLD}▶ SUITE FAILED ◀${NC}"
  exit 1
fi
echo -e "${GREEN}${BOLD}▶ ALL SUITES PASSED ◀${NC}"
exit 0
