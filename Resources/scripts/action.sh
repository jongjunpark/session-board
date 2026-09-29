#!/bin/bash
# 메뉴 막대에서 누른 동작 처리
#   open <local session id>   앱에서 세션 열기
#   open-app <bundle id>      터미널 세션을 띄운 앱을 앞으로
#   check <cli session id>    목록에서 지우기
#   check-done                완료 항목 전부 지우기
#   snooze <cli session id>   오래 걸리는 백그라운드 알림을 한 번 더 미루기
set -u
DIR="$HOME/.claude/session-board/state"
case "${1:-}" in
  open)  open "claude://claude.ai/epitaxy/$2" ;;
  open-app) [ -n "$2" ] && open -b "$2" ;; # 터미널 세션: 띄운 앱(iTerm 등)을 앞으로
  check) rm -f "$DIR/$2.json" ;;
  snooze)
    f="$DIR/$2.json"
    [ -f "$f" ] || exit 0
    wait=$(sed -n 's/^BG_WARN_SEC=\([0-9]*\).*/\1/p' "$HOME/.claude/session-board/bin/board-json.sh")
    tmp=$(mktemp "$DIR/.tmp.XXXXXX")
    jq --argjson until "$(( $(date +%s) + ${wait:-900} ))" '.bg_snooze_until = $until | .bg_warned = false' "$f" >"$tmp" && mv "$tmp" "$f"
    ;;
  check-done)
    for f in "$DIR"/*.json; do
      [ -f "$f" ] && [ "$(jq -r '.state == "done" and ((.bg // []) | length) == 0' "$f")" = true ] && rm -f "$f"
    done
    ;;
esac
