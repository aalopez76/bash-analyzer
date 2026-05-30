#!/bin/bash
# ============================================================
# TEST — Dependency preflight (functions/common.sh:require_tools)
# ============================================================
# Verifies require_tools(): succeeds when all tools are present and
# aborts with a clear, naming message when one is missing.
#
# Portability note: we exercise the real require_tools function with a
# bogus tool name in a subshell rather than manipulating PATH with
# symlinks — symlink creation is unavailable under Git Bash on Windows.
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$SCRIPT_DIR")"
cd "$PROJ"

PASS=0; FAIL=0
ok()  { echo "  PASS — $1"; PASS=$((PASS + 1)); }
bad() { echo "  FAIL — $1"; FAIL=$((FAIL + 1)); }

echo "=== DEPENDENCY PREFLIGHT TEST ==="

# Sourcing runs the real preflight over the core utilities and defines
# require_tools(). If a core tool were missing this would abort here.
# shellcheck source=functions/common.sh
source functions/common.sh >/dev/null 2>&1
ok "common.sh sources cleanly (real preflight passed)"

BOGUS="definitely_not_a_real_tool_xyz123"

# Missing tool: run in a subshell so require_tools' exit 1 is contained.
msg=$( require_tools "$BOGUS" 2>&1 )
rc=$?
[ "$rc" -ne 0 ] && ok "non-zero exit when a tool is missing (rc=$rc)" \
                || bad "expected non-zero exit, got 0"
case "$msg" in
  *"$BOGUS"*) ok "error message names the missing tool" ;;
  *)          bad "error did not name the missing tool: $msg" ;;
esac

# All-present: require_tools returns success for tools we know exist.
if ( require_tools awk grep sort ); then
  ok "returns success when given present tools"
else
  bad "wrongly failed for present tools"
fi

# Reports every missing tool at once.
msg=$( require_tools "${BOGUS}_a" "${BOGUS}_b" 2>&1 ) || true
if [[ "$msg" == *"${BOGUS}_a"* && "$msg" == *"${BOGUS}_b"* ]]; then
  ok "lists every missing tool in one message"
else
  bad "did not list all missing tools: $msg"
fi

echo ""
echo "RESULT  passed=$PASS  failed=$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
