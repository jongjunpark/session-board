#!/bin/bash
# CLI 세션 id → 데스크톱 앱 세션 정보 {id,title,scheduled,archived}. 없으면 {}.
set -u
SESS="$HOME/Library/Application Support/Claude/claude-code-sessions"
f=$(grep -rlF --include='local_*.json' "\"$1\"" "$SESS" 2>/dev/null | head -1)
[ -z "$f" ] && { echo '{}'; exit 0; }
jq -c '{id: .sessionId, title: (.title // ""), scheduled: has("scheduledTaskId"), archived: (.isArchived // false)}' "$f"
