#!/bin/bash
# Claude Code 훅 → 세션 상태 기록 (running | needs_input | done)
# 상태 파일: ~/.claude/session-board/state/<cli session id>.json
# 훅 결정에 끼어들지 않도록 stdout 에는 아무것도 쓰지 않고 항상 exit 0.
set -u
exec 1>/dev/null

BOARD="$HOME/.claude/session-board"
DIR="$BOARD/state"
mkdir -p "$DIR"

input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input")
[ -z "$sid" ] && exit 0
event=$(jq -r '.hook_event_name // empty' <<<"$input")
tool=$(jq -r '.tool_name // empty' <<<"$input")
file="$DIR/$sid.json"
cur=""
[ -f "$file" ] && cur=$(jq -r '.state // empty' "$file" 2>/dev/null)

# write <state> <reason> <summary>
write() {
  local prev="null"
  [ -f "$file" ] && prev=$(cat "$file")
  local tmp
  tmp=$(mktemp "$DIR/.tmp.XXXXXX")
  jq -n \
    --arg sid "$sid" --arg state "$1" --arg reason "$2" --arg summary "$3" \
    --arg cwd "$(jq -r '.cwd // ""' <<<"$input")" \
    --arg transcript "$(jq -r '.transcript_path // ""' <<<"$input")" \
    --arg entrypoint "${CLAUDE_CODE_ENTRYPOINT:-}" \
    --arg bundle "${__CFBundleIdentifier:-}" \
    --argjson now "$(date +%s)" --argjson prev "$prev" '
    ($prev // {}) as $p
    | {
        session_id: $sid,
        state: $state,
        reason: $reason,
        summary: $summary,
        cwd: (if $cwd == "" then ($p.cwd // "") else $cwd end),
        transcript: (if $transcript == "" then ($p.transcript // "") else $transcript end),
        # cli = 터미널에서 직접 띄운 세션, sdk-cli = claude -p 같은 뒤에서 도는 실행, claude-desktop = 앱
        entrypoint: (if $entrypoint == "" then ($p.entrypoint // "") else $entrypoint end),
        # 세션을 띄운 앱(iTerm, 터미널, VS Code 등). 눌렀을 때 이 앱을 앞으로 가져온다
        app_bundle: (if $bundle == "" then ($p.app_bundle // "") else $bundle end),
        # 새 요청으로 다시 돌기 시작할 때만 시작 시각을 새로 잡는다
        started_at: (if $state == "running" and (($p.state // "") | IN("running", "needs_input") | not)
                     then $now else ($p.started_at // $now) end),
        updated_at: $now,
        # 아직 끝나지 않은 백그라운드 작업 (board-json.sh 가 완료 알림을 보고 지운다)
        bg: ($p.bg // []),
        bg_snooze_until: ($p.bg_snooze_until // 0),
        bg_warned: ($p.bg_warned // false)
      }' >"$tmp" && mv "$tmp" "$file"
}

# 백그라운드로 띄운 도구(Bash·Agent 등)를 기록한다
add_bg() {
  [ "$(jq -r '.tool_input.run_in_background // false' <<<"$input")" = "true" ] || return 0
  [ -f "$file" ] || return 0
  local tmp
  tmp=$(mktemp "$DIR/.tmp.XXXXXX")
  jq --argjson in "$input" --argjson now "$(date +%s)" '
    .bg = ((.bg // []) + [{
      tool_use_id: ($in.tool_use_id // ""),
      task_id: ($in.tool_response.backgroundTaskId // $in.tool_response.agentId // $in.tool_response.taskId // ""),
      what: (($in.tool_input.description // $in.tool_input.command // $in.tool_name // "") | tostring | .[0:60]),
      at: $now
    }])' "$file" >"$tmp" && mv "$tmp" "$file"
}

notify_needs_input() {
  [ "$cur" = "needs_input" ] && return
  "$BOARD/bin/notify.sh" "$sid" "$1" >/dev/null 2>&1 &
}

case "$event" in
  UserPromptSubmit)
    write running "" ""
    ;;
  PreToolUse)
    case "$tool" in
      AskUserQuestion) notify_needs_input "질문에 답해 주세요"; write needs_input "질문에 답해 주세요" "" ;;
      ExitPlanMode)    notify_needs_input "계획을 승인해 주세요"; write needs_input "계획을 승인해 주세요" "" ;;
    esac
    ;;
  PermissionRequest)
    notify_needs_input "권한 승인: $tool"
    write needs_input "권한 승인: $tool" ""
    ;;
  Notification)
    case "$(jq -r '.notification_type // empty' <<<"$input")" in
      permission_prompt|elicitation_dialog)
        msg=$(jq -r '.message // "확인이 필요해요"' <<<"$input")
        notify_needs_input "$msg"
        write needs_input "$msg" ""
        ;;
    esac
    ;;
  PostToolUse|PostToolUseFailure|PermissionDenied)
    # 도구가 돌았으면 진행중. 기록이 없던 세션(보드 설치 전에 시작)이나
    # 새 요청 없이 다시 깨어난 세션(백그라운드 작업 완료 알림 등)도 여기서 올라온다
    if [ "$cur" = "running" ]; then
      touch "$file" # 마지막 움직임 시각 = 파일 수정 시각
    else
      write running "" ""
    fi
    [ "$event" = "PostToolUse" ] && add_bg
    # 백그라운드 작업을 직접 멈춘 경우엔 완료 알림이 오지 않으므로 여기서 뺀다
    case "$tool" in
      TaskStop|KillShell|KillBash)
        stopped=$(jq -r '.tool_input.task_id // .tool_input.shell_id // empty' <<<"$input")
        if [ -n "$stopped" ] && [ -f "$file" ]; then
          tmp=$(mktemp "$DIR/.tmp.XXXXXX")
          jq --arg id "$stopped" '.bg = ((.bg // []) | map(select(.task_id != $id)))' "$file" >"$tmp" && mv "$tmp" "$file"
        fi
        ;;
    esac
    ;;
  Stop)
    # 마지막 답의 첫 줄 (마크다운 기호 제거, 글자 수 기준 80자)
    summary=$(jq -r '(.last_assistant_message // "")
      | split("\n") | map(select(test("^\\s*#") | not)) | map(gsub("\\[(?<t>[^\\]]*)\\]\\([^)]*\\)"; "\(.t)") | gsub("https?://\\S+"; "") | gsub("[*`>|]"; "") | sub("^[\\s#-]+"; "") | select(test("\\S")))
      | (.[0] // "") | .[0:80]' <<<"$input")
    write done "" "${summary:-}"
    ;;
  StopFailure)
    write done "오류로 멈춤" ""
    ;;
esac
exit 0
