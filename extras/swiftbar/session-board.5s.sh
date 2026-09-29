#!/bin/bash
# <xbar.title>Claude 세션 보드</xbar.title>
# <xbar.desc>진행중 · 확인 필요 · 완료 세션을 메뉴 막대에 모아 보여준다</xbar.desc>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideSwiftBar>false</swiftbar.hideSwiftBar>
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

BOARD="$HOME/.claude/session-board"
ACTION="$BOARD/bin/action.sh"

"$BOARD/bin/board-json.sh" | jq -r --arg action "$ACTION" '
  def clean: gsub("\\|"; "｜") | gsub("\n"; " ");
  def act($a; $b): "bash=\"\($action)\" param1=\($a) param2=\($b) terminal=false refresh=true";
  def openAct: if .kind == "terminal" then act("open-app"; .app_bundle) else act("open"; .local_id) end;

  map(.title |= clean) as $all
  | ($all | map(select(.state == "needs_input"))) as $need
  | ($all | map(select(.state == "running"))) as $run
  | ($all | map(select(.state == "done"))) as $done

  # 메뉴 막대 제목
  | ( [ (if ($need | length) > 0 then "\u001b[38;5;214m● \($need | length)\u001b[0m" else empty end),
        (if ($run | length) > 0 then "⟳ \($run | length)" else empty end),
        (if ($done | length) > 0 then "\u001b[38;5;71m✓ \($done | length)\u001b[0m" else empty end) ] | join("  ")) as $t
  | (if $t == "" then "| sfimage=checklist"
     else "\($t) | ansi=true" end),
    "---",

    (if ($need | length) > 0 then
       "확인 필요 \($need | length) | size=12 color=#e09a1a",
       ($need[] |
         "\(.title)  ·  \(.label | clean) | color=#e09a1a \(openAct)",
         "--세션 열기 | \(openAct)",
         (if .bg_warn then "--더 기다리기 (15분 뒤 다시 알림) | \(act("snooze"; .session_id))" else empty end))
     else empty end),

    (if ($run | length) > 0 then
       (if ($need | length) > 0 then "---" else empty end),
       "진행중 \($run | length) | size=12 color=gray",
       ($run[] |
         "\(.title)  ·  \(.label) | \(if .stale then "color=gray " else "" end)\(openAct)",
         "--세션 열기 | \(openAct)",
         "--목록에서 지우기 | \(act("check"; .session_id))")
     else empty end),

    (if ($done | length) > 0 then
       (if (($need | length) + ($run | length)) > 0 then "---" else empty end),
       "완료 \($done | length) | size=12 color=gray",
       ($done[] |
         "\(.title)  ·  \(.label | clean) | \(openAct)",
         (if .summary != "" then "--\(.summary | clean) | size=12 color=gray" else empty end),
         "--세션 열기 | \(openAct)",
         "--확인 완료 ✓ | \(act("check"; .session_id))"),
       "완료 전부 확인 ✓ | \(act("check-done"; "_"))"
     else empty end),

    (if ($all | length) == 0 then "지금 도는 세션이 없어요 | color=gray" else empty end),
    "---",
    "새로고침 | refresh=true"
'
