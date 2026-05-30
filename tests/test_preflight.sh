#!/bin/bash
# ============================================================
# TEST — Dependency preflight (functions/common.sh:require_tools)
# ============================================================
# Verifies that sourcing common.sh aborts with a clear message when a
# required tool is missing, and succeeds when all tools are present.
# ============================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(dirname "$SCRIPT_DIR")"
cd "$PROJ"

PASS=0; FAIL=0
ok()  { echo "  ✔ PASS — $1"; ((PASS++)); }
bad() { echo "  ✘ FAIL — $1"; ((FAIL++)); }

echo "=== DEPENDENCY PREFLIGHT TEST ==="

# ---------- All tools present: sourcing succeeds ----------
out=$(bash -c 'source functions/common.sh; echo SOURCED_OK' 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && echo "$out" | grep -q "SOURCED_OK"; then
  ok "sources cleanly when all tools are present"
else
  bad "clean source failed (rc=$rc): $out"
fi

# ---------- Missing tool: sourcing aborts with message ----------
# Shadow 'sha256sum' by giving the subshell a PATH that lacks it.
# We build a temp bin with only the tools we WANT, omitting sha256sum.
TMPBIN=$(mktemp -d)
trap 'rm -rf "$TMPBIN"' EXIT
for t in bash awk grep sort uniq head tail wc find mktemp tr dirname command env; do
  src=$(command -v "$t" 2>/dev/null) && ln -sf "$src" "$TMPBIN/$t"
done
# Note: sha256sum deliberately NOT linked.

out=$(PATH="$TMPBIN" bash -c 'source functions/common.sh; echo SHOULD_NOT_REACH' 2>&1)
rc=$?
if [ "$rc" -ne 0 ]; then ok "non-zero exit when a tool is missing (rc=$rc)"; else bad "expected non-zero exit, got 0"; fi
if echo "$out" | grep -q "sha256sum"; then ok "error names the missing tool (sha256sum)"; else bad "error did not name the missing tool: $out"; fi
if echo "$out" | grep -q "SHOULD_NOT_REACH"; then bad "execution continued past the missing-tool check"; else ok "execution aborted before continuing"; fi

echo ""
echo "=== RESULT  passed=$PASS  failed=$FAIL ==="
[ "$FAIL" -eq 0 ] || exit 1
exit 0
