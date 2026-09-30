#!/bin/bash
# 확인 필요 알림. 예약 루틴 세션은 건너뛴다.
#   notify.sh <session id> <사유> [claude|codex]
set -u
HERE="$(cd "$(dirname "$0")" && pwd)" # 이 스크립트가 있는 곳 (앱 안 Contents/Resources/scripts)
export PATH="/usr/bin:/opt/homebrew/bin:/usr/local/bin:/bin"
BOARD="$HOME/.claude/session-board"
agent="${3:-$(jq -r '.agent // "claude"' "$BOARD/state/$1.json" 2>/dev/null || echo claude)}"

if [ "$agent" = "codex" ]; then
  # Codex 스레드 제목 (Codex 로컬 DB, 읽지 못하면 기본 이름)
  title=""
  db=$(ls -t "$HOME"/.codex/state_*.sqlite 2>/dev/null | head -1)
  if [ -n "$db" ] && [[ "$1" =~ ^[0-9A-Za-z-]+$ ]]; then
    title=$(sqlite3 -readonly "$db" "SELECT COALESCE(NULLIF(name, ''), title, '') FROM threads WHERE id = '$1';" 2>/dev/null | head -1)
  fi
  [ -z "$title" ] && title="Codex 세션"
else
  meta=$("$HERE/lookup.sh" "$1")
  [ "$(jq -r '.scheduled // false' <<<"$meta")" = "true" ] && exit 0
  title=$(jq -r '.title // ""' <<<"$meta")
  [ -z "$title" ] && title="Claude 세션"
fi

osascript - "$title" "$2" <<'EOF'
on run argv
  display notification (item 2 of argv) with title "확인 필요" subtitle (item 1 of argv) sound name "Glass"
end run
EOF
