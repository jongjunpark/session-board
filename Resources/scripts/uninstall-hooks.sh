#!/bin/bash
# Claude Code 설정(~/.claude/settings.json)에서 세션 보드 훅만 뺀다. 앱 없이도 돌도록 jq 로 한다.
# (Homebrew 완전 제거 `brew uninstall --zap` 이 이걸 부른다)
set -u
export PATH="/usr/bin:/opt/homebrew/bin:/usr/local/bin:/bin"
SETTINGS="$HOME/.claude/settings.json"
HOOK="$HOME/.claude/session-board/bin/hook.sh"
[ -f "$SETTINGS" ] || exit 0
jq -e --arg h "$HOOK" '[.hooks // {} | .[] | .[]? | .hooks[]? | select(.command == $h)] | length > 0' "$SETTINGS" >/dev/null 2>&1 || exit 0

cp "$SETTINGS" "$SETTINGS.bak-session-board-$(date +%Y%m%d-%H%M%S)-uninstall"
tmp=$(mktemp "$SETTINGS.XXXXXX")
jq --arg h "$HOOK" '
  if .hooks then
    .hooks |= (with_entries(.value |= map(select(((.hooks // []) | map(.command) | index($h)) | not)))
               | with_entries(select(.value | length > 0)))
    | if (.hooks | length) == 0 then del(.hooks) else . end
  else . end' "$SETTINGS" >"$tmp" && mv "$tmp" "$SETTINGS"
