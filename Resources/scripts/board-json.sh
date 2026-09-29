#!/bin/bash
# 세션 보드 데이터 → JSON 배열 (확인 필요 → 진행중 → 완료, 각각 최근 순)
# 메뉴 막대 플러그인과 떠 있는 창이 같이 쓴다.
set -u
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

BOARD="$HOME/.claude/session-board"
DIR="$BOARD/state"
SESS="$HOME/Library/Application Support/Claude/claude-code-sessions"
IDX="$BOARD/.index.json"
STALE_SEC=600 # 진행중인데 이만큼 움직임이 없으면 경고
# 백그라운드 작업이 기준 시간을 넘게 돌면 확인 필요로 올린다 ("더 기다리기"로 같은 만큼 미룸).
# 켜기/끄기와 시간은 앱 설정 창에서 정하고 config.json 에 저장된다 (없으면 켜짐·15분)
CONFIG="$BOARD/config.json"
BG_WARN_ON=$(jq -r 'if .bgWarnEnabled == false then "false" else "true" end' "$CONFIG" 2>/dev/null || echo true)
BG_WARN_SEC=$(( $(jq -r '.bgWarnMinutes // 15' "$CONFIG" 2>/dev/null || echo 15) * 60 ))
mkdir -p "$DIR"

# 데스크톱 앱 세션 목록 → CLI 세션 id 색인 (앱 세션 파일이 바뀌었을 때만 다시 만든다)
if [ ! -f "$IDX" ] || [ -n "$(find "$SESS" -name 'local_*.json' -newer "$IDX" -print -quit 2>/dev/null)" ]; then
  find "$SESS" -name 'local_*.json' -print0 2>/dev/null \
    | xargs -0 jq -c '{id: .sessionId, title: (.title // ""), scheduled: has("scheduledTaskId"),
        archived: (.isArchived // false), cli: ([.cliSessionId] + (.priorCliSessionIds // []))}' 2>/dev/null \
    | jq -s 'map(. as $s | .cli[] | {key: ., value: ($s | del(.cli))}) | from_entries' >"$IDX.tmp.$$" \
    && mv "$IDX.tmp.$$" "$IDX"
fi

# 상태 파일 + 마지막 움직임 시각 (상태 파일과 대화 기록 중 늦은 쪽)
# 터미널 세션은 앱 제목이 없어서 대화 기록의 제목(/rename 으로 붙인 것 → 자동 제목 순)을 읽어 온다
states="[]"
for f in "$DIR"/*.json; do
  [ -f "$f" ] || continue
  mt=$(stat -f %m "$f")
  meta=$(jq -r '[.transcript // "", .entrypoint // ""] | @tsv' "$f" 2>/dev/null)
  tr=${meta%%$'\t'*}
  ep=${meta#*$'\t'}
  title=""
  if [ -n "$tr" ] && [ -f "$tr" ]; then
    tm=$(stat -f %m "$tr"); [ "$tm" -gt "$mt" ] && mt=$tm
    case "$ep" in
      cli|claude-vscode)
        title=$(grep '"type":"custom-title"' "$tr" | tail -1 | jq -r '.customTitle // empty' 2>/dev/null)
        [ -z "$title" ] && title=$(grep '"type":"ai-title"' "$tr" | tail -1 | jq -r '.aiTitle // empty' 2>/dev/null)
        ;;
    esac

    # Codex: 턴이 오류로 실패하면 Stop 훅이 오지 않는다. 대화 기록의 마지막 턴 기록을 보고 끝났는지 정한다.
    #   task_complete (error 있음) → 오류로 멈춤 / task_complete → 완료 / turn_aborted → 중단됨
    if [ "$(jq -r '.agent // ""' "$f")" = codex ] && [ "$(jq -r '.state' "$f")" != done ]; then
      last=$(LC_ALL=C /usr/bin/grep -E '"type":"(task_started|task_complete|turn_aborted)"' "$tr" | tail -1)
      ended=$(jq -rc '
        .payload as $p
        | if $p.type == "task_complete" then
            if $p.error != null then
              {reason: "오류로 멈춤",
               summary: ((($p.error.message // "") | (fromjson? // .) | if type == "object" then (.error.message // .message // tostring) else tostring end) | .[0:80])}
            else
              {reason: "",
               summary: (($p.last_agent_message // "") | split("\n") | map(select(test("\\S"))) | (.[0] // "") | .[0:80])}
            end
          elif $p.type == "turn_aborted" then {reason: "중단됨", summary: ""}
          else empty end' <<<"$last" 2>/dev/null)
      if [ -n "$ended" ]; then
        tmp=$(mktemp "$DIR/.tmp.XXXXXX")
        jq --argjson e "$ended" --argjson now "$(date +%s)" \
          '.state = "done" | .reason = $e.reason | .summary = (if $e.summary == "" then (.summary // "") else $e.summary end) | .updated_at = $now' \
          "$f" >"$tmp" && mv "$tmp" "$f"
      fi
    fi

    # Codex: 인터넷 등 권한 요청(request_permissions)·질문은 창이 떠 있는 동안 훅 신호가 없다.
    # 대화 기록 끝에 결과 없이 걸린 도구 호출이 그런 요청이면 확인 필요로 바꾸고 한 번 알린다.
    # (답하면 도구가 끝나며 오는 훅 신호로 진행중으로 돌아간다)
    if [ "$(jq -r '.agent // ""' "$f")" = codex ] && [ "$(jq -r '.state' "$f")" = running ]; then
      waiting=$(tail -n 80 "$tr" | jq -rs '
        [ .[] | select(.type? == "response_item") | .payload
          | select(.type | IN("function_call", "custom_tool_call", "function_call_output", "custom_tool_call_output")) ] as $items
        | ($items | map(select(.type | endswith("_output")) | .call_id)) as $answered
        | [ $items[] | select((.type | endswith("_output")) | not) | select(.call_id as $c | ($answered | index($c)) | not) ]
        | last
        | if . == null then ""
          else ((.name // "") + " " + ((.arguments // .input // "") | tostring)) as $call
            | if ($call | test("request_permissions")) then "권한 승인을 기다려요"
              elif ($call | test("request_user_input")) then "질문에 답해 주세요"
              else "" end
          end' 2>/dev/null)
      if [ -n "$waiting" ]; then
        tmp=$(mktemp "$DIR/.tmp.XXXXXX")
        jq --arg r "$waiting" '.state = "needs_input" | .reason = $r' "$f" >"$tmp" && mv "$tmp" "$f"
        "$BOARD/bin/notify.sh" "$(jq -r .session_id "$f")" "$waiting" codex >/dev/null 2>&1 &
      fi
    fi

    # Codex 명령: 끝 신호(PostToolUse)를 끝내 못 받은 기록은 6시간 뒤 정리한다 (창을 닫았거나 /stop 등)
    if [ "$(jq -r '[.bg // [] | .[] | select(.kind == "command" and (now - .at) > 21600)] | length' "$f")" -gt 0 ]; then
      tmp=$(mktemp "$DIR/.tmp.XXXXXX")
      jq '.bg = ((.bg // []) | map(select(.kind != "command" or (now - .at) <= 21600)))' "$f" >"$tmp" && mv "$tmp" "$f"
    fi

    # 백그라운드 작업: 대화 기록에 완료 알림(<task-notification>)이 온 것은 목록에서 뺀다
    if [ "$(jq '(.bg // []) | length' "$f")" -gt 0 ]; then
      # 완료가 확인된 호출 번호만 모은다
      finished=$(jq -c '.bg[]' "$f" | while IFS= read -r b; do
        tu=$(jq -r '.tool_use_id' <<<"$b"); ti=$(jq -r '.task_id' <<<"$b")
        # 진짜 완료 알림은 작업 번호 바로 뒤에 도구 호출 번호가 붙어 나온다 (대화 중에 번호만 언급된 것과 구분)
        if [ -n "$tu" ] && [ -n "$ti" ] \
          && grep -qF "<task-id>${ti}</task-id>\\n<tool-use-id>${tu}</tool-use-id>" "$tr"; then echo "$tu"; fi
      done | jq -Rsc 'split("\n") | map(select(. != ""))')
      # 그 번호만 뺀다. 목록을 통째로 덮어쓰면 그사이 훅이 새로 넣은 작업이 사라진다
      if [ "$finished" != "[]" ]; then
        tmp=$(mktemp "$DIR/.tmp.XXXXXX")
        jq --argjson done "$finished" '.bg = ((.bg // []) | map(select(.tool_use_id as $t | $done | index($t) | not)))
          | if (.bg | length) == 0 then .bg_warned = false else . end' "$f" >"$tmp" && mv "$tmp" "$f"
      fi
      # 너무 오래 도는 작업이 있으면 알림을 한 번 보낸다
      now=$(date +%s)
      oldest=$(jq -r '
        (if (.agent // "") == "codex"
         then (if .state == "done" then ((.bg // []) | map(.at = ([.at, (.updated_at // 0)] | max))) else [] end)
         else (.bg // []) end)
        | if length > 0 then (min_by(.at).at) else 0 end' "$f")
      if [ "$BG_WARN_ON" = true ] && [ "$oldest" -gt 0 ] && [ $((now - oldest)) -gt $BG_WARN_SEC ] \
        && [ "$now" -gt "$(jq -r '.bg_snooze_until // 0' "$f")" ] && [ "$(jq -r '.bg_warned // false' "$f")" != true ]; then
        what="백그라운드 작업"; [ "$(jq -r '.agent // ""' "$f")" = codex ] && what="명령"
        "$BOARD/bin/notify.sh" "$(jq -r .session_id "$f")" "$what $(( (now - oldest) / 60 ))분째, 멈췄는지 확인해 보세요" "$(jq -r '.agent // "claude"' "$f")" >/dev/null 2>&1 &
        tmp=$(mktemp "$DIR/.tmp.XXXXXX")
        jq '.bg_warned = true' "$f" >"$tmp" && mv "$tmp" "$f"
      fi
    fi
  fi
  states=$(jq -c --argjson mt "$mt" --arg path "$f" --arg title "$title" --slurpfile s "$f" \
    '. + [$s[0] + {mtime: $mt, path: $path, transcript_title: $title}]' <<<"$states" 2>/dev/null || echo "$states")
done

# Codex 스레드 제목·출처·보관 여부. Codex 가 로컬 DB 에 둔다 (파일 이름의 숫자가 바뀌어도 가장 최근 것을 쓴다).
# 읽지 못하면 비워 두고, 제목은 폴더 이름으로 대신한다.
CIDX="{}"
if jq -e 'any(.[]; .agent == "codex")' <<<"$states" >/dev/null 2>&1; then
  CDB=$(ls -t "$HOME"/.codex/state_*.sqlite 2>/dev/null | head -1)
  ids=$(jq -r '[.[] | select(.agent == "codex") | .session_id | select(test("^[0-9A-Za-z-]+$")) | "\u0027" + . + "\u0027"] | join(",")' <<<"$states")
  if [ -n "$CDB" ] && [ -n "$ids" ]; then
    CIDX=$(sqlite3 -readonly -json "$CDB" "SELECT id, COALESCE(NULLIF(name, ''), title, '') AS title, source, archived FROM threads WHERE id IN ($ids);" 2>/dev/null \
      | jq -c 'map({key: .id, value: .}) | from_entries' 2>/dev/null)
    [ -n "$CIDX" ] || CIDX="{}"
  fi
fi

# Claude 앱 세션이면 앱 정보, 터미널 세션이면 터미널 표시, Codex 면 Codex 정보. 셋 다 아니면(claude -p 등) null
FILTER_COMMON='
  def terminal: (.entrypoint // "") | IN("cli", "claude-vscode");
  def source($idx; $cidx): . as $s
    | if ($s.agent // "claude") == "codex" then {kind: "codex", m: $cidx[$s.session_id]}
      else ($idx[$s.session_id]) as $m
        | if $m != null then {kind: "app", m: $m}
          elif ($s | terminal) then {kind: "terminal", m: null}
          else null end
      end;
  # 보관한 Codex 스레드와 codex exec 처럼 뒤에서 도는 실행은 뺀다
  def codexHidden($src): $src.kind == "codex" and ((($src.m.archived // 0) == 1) or (($src.m.source // "") == "exec"));
  def bgcount: (.bg // []) | length;
'

# 지울 것:
#  - 앱에도 터미널에도 속하지 않는 실행(claude -p 등)은 하루 뒤
#  - 보관·예약 루틴 앱 세션은 바로
#  - 보관한 Codex 스레드, codex exec 실행은 바로
#  - 터미널·Codex 세션이 완료 아닌 채로 하루 넘게 소식이 없으면 (창을 닫았거나 멈춘 것)
jq -r --slurpfile idx "$IDX" --argjson cidx "$CIDX" --argjson now "$(date +%s)" "$FILTER_COMMON"'
  .[] | . as $s | ($s | source($idx[0]; $cidx)) as $src
  | select(
      ($src == null and ($now - $s.updated_at) > 86400)
      or ($src.kind == "app" and (($src.m.archived // false) or ($src.m.scheduled // false)))
      or codexHidden($src)
      or (($src.kind == "terminal" or $src.kind == "codex") and $s.state != "done" and ($now - $s.mtime) > 86400))
  | .path' <<<"$states" | while IFS= read -r p; do rm -f "$p"; done

jq -c --slurpfile idx "$IDX" --argjson cidx "$CIDX" --argjson now "$(date +%s)" --argjson stale "$STALE_SEC" --argjson bgwarn "$BG_WARN_SEC" --argjson bgon "$BG_WARN_ON" "$FILTER_COMMON"'
  # 큰 단위 하나만: 방금 · N분 · N시간 · N일
  def dur: if . < 60 then "방금" elif . < 3600 then "\(. / 60 | floor)분"
           elif . < 86400 then "\(. / 3600 | floor)시간" else "\(. / 86400 | floor)일" end;
  def rank: {needs_input: 0, running: 1, done: 2}[.state] // 3;

  [ .[] | . as $s | ($s | source($idx[0]; $cidx)) as $src
    | select($src != null)
    | select($src.kind != "app" or (($src.m.archived | not) and ($src.m.scheduled | not)))
    | select(codexHidden($src) | not)
    | ($now - $s.started_at) as $el | ($now - $s.mtime) as $idle
    | ($s.cwd | split("/") | last) as $folder
    # 백그라운드 작업 목록. Codex 명령은 턴이 끝난 뒤에도 남아 도는 것만 백그라운드로 본다
    # (턴 안에서 도는 명령은 표시·경고하지 않는다). 나이도 턴이 끝난 때부터 잰다
    | (if $src.kind == "codex"
       then (if $s.state == "done" then (($s.bg // []) | map(.at = ([.at, $s.updated_at] | max))) else [] end)
       else ($s.bg // []) end) as $bglist
    | ($bglist | length) as $bgn
    # 터미널에서 띄운 Codex CLI 세션인지 (띄운 앱이 비어 있거나 Codex 앱이면 앱 세션)
    | ($src.kind == "codex" and (($s.app_bundle // "") | IN("", "com.openai.codex") | not)) as $codexTerminal
    | (if $bgn > 0 then $now - ($bglist | min_by(.at).at) else 0 end) as $bgage
    # 백그라운드 작업이 기준 시간을 넘겼고 "더 기다리기"로 미룬 시간도 지났으면 확인 필요
    | ($bgon and $bgn > 0 and $bgage > $bgwarn and $now > ($s.bg_snooze_until // 0)) as $bgwarned
    # 화면에 보일 상태: 확인 필요 > 오래 걸리는 백그라운드 > 답은 끝났지만 백그라운드가 도는 중 > 원래 상태
    | (if $s.state == "needs_input" then "needs_input"
       elif $bgwarned then "needs_input"
       elif $bgn > 0 and $s.state == "done" then "running"
       else $s.state end) as $state
    # Claude 는 백그라운드 작업, Codex 는 실행 중인 명령
    | (if $src.kind == "codex" then "명령" else "백그라운드 작업" end) as $bgword
    | (if $bgn > 1 then "\($bgword) \($bgn)개" else $bgword end) as $bgname
    | {
        session_id: $s.session_id,
        kind: $src.kind,
        agent: (if $src.kind == "codex" then "codex" else "claude" end),
        local_id: (if $src.kind == "app" then $src.m.id elif $src.kind == "codex" then $s.session_id else "" end),
        app_bundle: ($s.app_bundle // ""),
        title: (if $src.kind == "app" then (if ($src.m.title // "") == "" then $folder else $src.m.title end)
                elif $src.kind == "codex" then
                  (($src.m.title // "") | (split("\n")[0] // "") | .[0:60]) as $t | (if $t == "" then $folder else $t end)
                elif ($s.transcript_title // "") != "" then $s.transcript_title
                else $folder end),
        state: $state,
        reason: ($s.reason // ""),
        summary: (($s.summary // "") | gsub("\\[(?<t>[^\\]]*)\\]\\([^)]*\\)?"; "\(.t)") | gsub("https?://\\S+"; "") | gsub("\\s+"; " ") | ltrimstr(" ") | rtrimstr(" ")),
        stale: ($state == "running" and $bgn == 0 and $idle > $stale),
        bg_count: $bgn,
        # 오래 걸리는 백그라운드 때문에 확인 필요가 된 항목 ("더 기다리기" 버튼)
        bg_warn: ($bgwarned and $s.state != "needs_input"),
        updated_at: $s.updated_at,
        # 호버 때 뜨는 짧은 목록용 한 단어 표시
        short: (if $state == "needs_input" then (if $bgwarned and $s.state != "needs_input" then "\(if $src.kind == "codex" then "명령" else "백그라운드" end) \($bgage | dur)" else "확인 필요" end)
                elif $bgn > 0 and $s.state == "done" then "\(if $src.kind == "codex" then "명령" else "백그라운드" end) \($bgage | dur)"
                elif $state == "running" then (if $el < 60 then "방금" else ($el | dur) end)
                else "\(($now - $s.updated_at) | dur) 전" end),
        label: (
          # 어느 도구인지는 화면이 제목 앞 기호로 보여 준다 (agent). 터미널 세션만 폴더를 붙인다
          (if $src.kind == "terminal" or $codexTerminal then "터미널 · \($folder) · " else "" end)
          + (if $s.state == "needs_input" then ($s.reason // "확인이 필요해요")
             elif $bgwarned then "\($bgname) \($bgage | dur)째 · 멈췄는지 확인해 보세요"
             elif $bgn > 0 and $s.state == "done" then "\($bgname) \($bgage | dur)째"
             elif $state == "running" then
               (if $el < 60 then "방금 시작" else "\($el | dur)째" end)
               + (if $bgn > 0 then " · \($bgname)" else "" end)
               + (if $bgn == 0 and $idle > $stale then " · \($idle | dur)째 소식 없음" else "" end)
             else "\(($now - $s.updated_at) | dur) 전 끝남" + (if ($s.reason // "") != "" then " (\($s.reason))" else "" end)
             end))
      } ]
  | sort_by(rank, -.updated_at)
' <<<"$states"
