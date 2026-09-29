#!/bin/bash
# Claude Code(~/.claude/settings.json)와 Codex(~/.codex/hooks.json) 설정에서 세션 보드 훅만 뺀다.
# 앱 없이도 돌도록 jq 로 한다. (Homebrew 완전 제거 `brew uninstall --zap` 이 이걸 부른다)
set -u
export PATH="/usr/bin:/opt/homebrew/bin:/usr/local/bin:/bin"
HOOK="$HOME/.claude/session-board/bin/hook.sh"

# remove_from <설정 파일> <훅 명령>
remove_from() {
  local file="$1" command="$2"
  [ -f "$file" ] || return 0
  jq -e --arg h "$command" '[.hooks // {} | .[] | .[]? | .hooks[]? | select(.command == $h)] | length > 0' \
    "$file" >/dev/null 2>&1 || return 0
  cp "$file" "$file.bak-session-board-$(date +%Y%m%d-%H%M%S)-uninstall"
  local tmp
  tmp=$(mktemp "$file.XXXXXX")
  jq --arg h "$command" '
    if .hooks then
      .hooks |= (with_entries(.value |= map(select(((.hooks // []) | map(.command) | index($h)) | not)))
                 | with_entries(select(.value | length > 0)))
      | if (.hooks | length) == 0 then del(.hooks) else . end
    else . end' "$file" >"$tmp" && mv "$tmp" "$file"
}

remove_from "$HOME/.claude/settings.json" "$HOOK"
remove_from "$HOME/.codex/hooks.json" "$HOOK --agent codex"
