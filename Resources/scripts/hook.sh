#!/bin/bash
# Claude Code / Codex 훅 → 세션 상태 기록 (running | needs_input | done)
# 상태 파일: ~/.claude/session-board/state/<session id>.json
# Codex 훅은 `hook.sh --agent codex` 로 부른다 (두 도구의 입력 형식은 거의 같다)
# 훅 결정에 끼어들지 않도록 stdout 에는 아무것도 쓰지 않고 항상 exit 0.
set -u
exec 1>/dev/null
umask 077 # 기록 파일은 나만 읽게
HERE="$(cd "$(dirname "$0")" && pwd)" # 이 스크립트가 있는 곳 (앱 안 Contents/Resources/scripts)

AGENT="claude"
[ "${1:-}" = "--agent" ] && AGENT="${2:-claude}"

BOARD="$HOME/.claude/session-board"
DIR="$BOARD/state"
mkdir -p "$DIR" && chmod 700 "$BOARD" "$DIR" 2>/dev/null

input=$(cat)
sid=$(jq -r '.session_id // empty' <<<"$input")
# 세션 번호는 파일 이름이 되므로 영문·숫자·- 만 받는다 (../ 로 기록 폴더 밖에 쓰지 못하게)
[[ "$sid" =~ ^[A-Za-z0-9-]+$ ]] || exit 0
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
    --arg agent "$AGENT" \
    --arg entrypoint "$( [ "$AGENT" = claude ] && echo "${CLAUDE_CODE_ENTRYPOINT:-}" )" \
    --arg bundle "${__CFBundleIdentifier:-}" \
    --argjson now "$(date +%s)" --argjson prev "$prev" '
    ($prev // {}) as $p
    | {
        session_id: $sid,
        agent: $agent, # claude | codex
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
# Codex: 명령(Bash) 이 시작되면 기록하고, 짝이 되는 PostToolUse 가 오면 뺀다.
# (Claude 의 백그라운드 작업과 같은 bg 목록을 쓰되, 완료 알림 대신 tool_use_id 로 짝을 맞춘다)
codex_cmd_start() {
  [ -f "$file" ] || return 0
  local tmp
  tmp=$(mktemp "$DIR/.tmp.XXXXXX")
  jq --argjson in "$input" --argjson now "$(date +%s)" '
    .bg = ((.bg // []) + [{
      tool_use_id: ($in.tool_use_id // ""),
      task_id: "",
      kind: "command",
      what: (($in.tool_input.command // $in.tool_name // "") | tostring | .[0:60]),
      at: $now
    }])' "$file" >"$tmp" && mv "$tmp" "$file"
}

codex_cmd_end() {
  [ -f "$file" ] || return 0
  local id tmp
  id=$(jq -r '.tool_use_id // empty' <<<"$input")
  [ -n "$id" ] || return 0
  tmp=$(mktemp "$DIR/.tmp.XXXXXX")
  jq --arg id "$id" '.bg = ((.bg // []) | map(select(.tool_use_id != $id)))' "$file" >"$tmp" && mv "$tmp" "$file"
}

add_bg() {
  # 뒤에서 도는 작업은 끝나면 대화 기록에 <task-id>작업 번호</task-id> + <tool-use-id>호출 번호</tool-use-id> 완료 알림이 온다.
  # 그 작업 번호를 돌려주는 호출을 도구 이름과 상관없이 모두 백그라운드 작업으로 기록한다 (지난 60일 기록으로 확인한 모양):
  #   명령(Bash, run_in_background 이거나 시간 초과로 넘어간 것) → backgroundTaskId
  #   에이전트(요청했거나 알아서 넘어간 것) → isAsync / status "async_launched" + agentId
  #   Monitor·Workflow 등 → taskId,  멈춘 에이전트를 SendMessage 로 다시 깨움 → resumedAgentId
  local task
  task=$(jq -r '.tool_response as $r
    | if ($r | type) != "object" then ""
      elif ($r.backgroundTaskId // "") != "" then $r.backgroundTaskId
      elif ($r.taskId // "") != "" then $r.taskId
      elif ($r.resumedAgentId // "") != "" then $r.resumedAgentId
      elif ($r.isAsync == true or $r.status == "async_launched") and ($r.agentId // "") != "" then $r.agentId
      else "" end
    # 구조화된 값이 없을 때는 결과 문구에서 번호를 읽는다
    | if . != "" then .
      else ($r | tostring) as $t
        | (($t | capture("Async agent launched[^\n]*?agentId: (?<id>[A-Za-z0-9]+)")? // null)
           // ($t | capture("[Rr]unning in background with ID: (?<id>[A-Za-z0-9]+)")? // null)
           // ($t | capture("moved to the background \\(ID: (?<id>[A-Za-z0-9]+)")? // null)
           // {id: ""}).id
      end' <<<"$input")
  [ -n "$task" ] || return 0
  [ -f "$file" ] || return 0
  local tmp
  tmp=$(mktemp "$DIR/.tmp.XXXXXX")
  jq --argjson in "$input" --arg task "$task" --argjson now "$(date +%s)" '
    .bg = ((.bg // []) + [{
      tool_use_id: ($in.tool_use_id // ""),
      task_id: $task,
      what: (($in.tool_input.description // $in.tool_input.command // $in.tool_name // "") | tostring | .[0:60]),
      at: $now
    }])' "$file" >"$tmp" && mv "$tmp" "$file"
}

notify_needs_input() {
  [ "$cur" = "needs_input" ] && return
  "$HERE/notify.sh" "$sid" "$1" "$AGENT" >/dev/null 2>&1 &
}

case "$event" in
  UserPromptSubmit)
    write running "" ""
    ;;
  PreToolUse)
    case "$tool" in
      AskUserQuestion) notify_needs_input "질문에 답해 주세요"; write needs_input "질문에 답해 주세요" "" ;;
      ExitPlanMode)    notify_needs_input "계획을 승인해 주세요"; write needs_input "계획을 승인해 주세요" "" ;;
      request_user_input*) notify_needs_input "질문에 답해 주세요"; write needs_input "질문에 답해 주세요" "" ;; # Codex
      Bash) # Codex: 명령 시작 (진행중으로 올리고 실행 중인 명령으로 기록)
        if [ "$AGENT" = codex ]; then
          [ "$cur" = "running" ] || write running "" ""
          codex_cmd_start
        fi
        ;;
    esac
    ;;
  PermissionRequest)
    # 질문·계획 승인처럼 이미 더 정확한 사유를 적어 둔 대기는 덮어쓰지 않는다
    if [ "$cur" != "needs_input" ]; then
      notify_needs_input "권한 승인: $tool"
      write needs_input "권한 승인: $tool" ""
    fi
    ;;
  Notification)
    case "$(jq -r '.notification_type // empty' <<<"$input")" in
      permission_prompt|elicitation_dialog)
        [ "$cur" = "needs_input" ] && exit 0 # 위와 같은 이유로 덮어쓰지 않는다
        msg=$(jq -r '.message // "확인이 필요해요"' <<<"$input")
        # Claude Code 의 영어 알림 문구를 옮긴다: "Claude needs your permission to use Bash" → "권한 승인: Bash"
        asked=$(sed -n 's/^Claude needs your permission to use \(.*\)$/\1/p' <<<"$msg")
        case "$asked" in
          "") ;;
          AskUserQuestion) msg="질문에 답해 주세요" ;;
          ExitPlanMode) msg="계획을 승인해 주세요" ;;
          *) msg="권한 승인: $asked" ;;
        esac
        notify_needs_input "$msg"
        write needs_input "$msg" ""
        ;;
    esac
    ;;
  PostToolUse|PostToolUseFailure|PermissionDenied)
    # Codex 앱의 질문(request_user_input_async)은 창을 띄우자마자 도구가 끝나고 답을 따로 기다린다.
    # 그래서 이 도구가 끝난 신호는 "답을 기다리는 중"으로 본다.
    # (인터넷 등 권한 요청 request_permissions 는 답한 뒤에야 끝나므로 여기가 아니라
    #  board-json.sh 가 대화 기록에 결과 없이 걸린 호출을 보고 잡는다)
    if [ "$AGENT" = codex ] && [[ "$tool" == request_user_input* ]]; then
      [ "$cur" = "needs_input" ] || notify_needs_input "질문에 답해 주세요"
      write needs_input "질문에 답해 주세요" ""
      exit 0
    fi
    # 도구가 돌았으면 진행중. 기록이 없던 세션(보드 설치 전에 시작)이나
    # 새 요청 없이 다시 깨어난 세션(백그라운드 작업 완료 알림 등)도 여기서 올라온다
    if [ "$cur" = "running" ]; then
      touch "$file" # 마지막 움직임 시각 = 파일 수정 시각
    else
      write running "" ""
    fi
    [ "$event" = "PostToolUse" ] && [ "$AGENT" = claude ] && add_bg # 백그라운드 작업 추적은 Claude 만
    [ "$AGENT" = codex ] && codex_cmd_end # Codex: 끝난 명령은 실행 중 목록에서 뺀다
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
  Interrupt) # Codex: 도중에 멈춤 (도는 명령도 함께 멈추므로 실행 중 목록을 비운다)
    write done "중단됨" ""
    tmp=$(mktemp "$DIR/.tmp.XXXXXX")
    jq '.bg = []' "$file" >"$tmp" && mv "$tmp" "$file"
    ;;
esac
exit 0
