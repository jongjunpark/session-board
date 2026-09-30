#!/bin/bash
# Claude Code(~/.claude/settings.json)와 Codex(~/.codex/hooks.json) 설정에서 SessionBoard 훅만 뺀다.
# 앱 없이도 돌도록 jq 로 한다. (Homebrew 완전 제거 `brew uninstall --zap` 이 이걸 부른다)
# 훅이 가리키는 스크립트는 버전에 따라 두 곳이라 둘 다 SessionBoard 훅으로 본다:
#   ~/.claude/session-board/bin/hook.sh              (v0.3.4 까지)
#   …/SessionBoard.app/Contents/Resources/scripts/hook.sh (그 뒤)
set -u
export PATH="/usr/bin:/opt/homebrew/bin:/usr/local/bin:/bin"
PATTERN='(/\.claude/session-board/bin/hook\.sh|SessionBoard\.app/Contents/Resources/scripts/hook\.sh)'

# remove_from <설정 파일>
remove_from() {
  local file="$1"
  [ -f "$file" ] || return 0
  jq -e --arg p "$PATTERN" '[.hooks // {} | .[] | .[]? | .hooks[]? | select((.command // "") | test($p))] | length > 0' \
    "$file" >/dev/null 2>&1 || return 0
  cp -p "$file" "$file.bak-session-board-$(date +%Y%m%d-%H%M%S)-uninstall"
  local tmp
  tmp=$(mktemp "$file.XXXXXX")
  jq --arg p "$PATTERN" '
    if .hooks then
      .hooks |= (with_entries(.value |= map(select(((.hooks // []) | any((.command // "") | test($p))) | not)))
                 | with_entries(select(.value | length > 0)))
      | if (.hooks | length) == 0 then del(.hooks) else . end
    else . end' "$file" >"$tmp" \
    && chmod "$(stat -f %Lp "$file")" "$tmp" \
    && mv "$tmp" "$file" # 원래 파일 권한 그대로
}

remove_from "$HOME/.claude/settings.json"
remove_from "$HOME/.codex/hooks.json"
