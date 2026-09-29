#!/bin/bash
# 확인 필요 알림. 예약 루틴 세션은 건너뛴다.
set -u
BOARD="$HOME/.claude/session-board"
meta=$("$BOARD/bin/lookup.sh" "$1")
[ "$(jq -r '.scheduled // false' <<<"$meta")" = "true" ] && exit 0
title=$(jq -r '.title // ""' <<<"$meta")
[ -z "$title" ] && title="Claude 세션"
osascript - "$title" "$2" <<'EOF'
on run argv
  display notification (item 2 of argv) with title "확인 필요" subtitle (item 1 of argv) sound name "Glass"
end run
EOF
