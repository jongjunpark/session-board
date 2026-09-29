#!/bin/bash
# CHANGELOG.md 에서 한 버전의 절만 뽑는다:  ./scripts/release-notes.sh 0.2.5
set -euo pipefail
cd "$(dirname "$0")/.."
awk -v tag="## v$1" '
  $0 == tag { on = 1; next }
  on && /^## v/ { exit }
  on { print }
' CHANGELOG.md | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}'
