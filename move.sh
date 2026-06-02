#!/bin/bash

# Strict mode: -u (unset vars) + pipefail. 'errexit' omitted — the
# compgen guard below intentionally returns non-zero when there is
# nothing to archive.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1
mkdir -p history
compgen -G "output/*.txt" > /dev/null 2>&1 && mv output/*.txt history/
