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
BG_WARN_SEC=900 # 백그라운드 작업이 이만큼 넘게 돌면 확인 필요로 올린다 ("더 기다리기"로 같은 만큼 미룸)
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
      oldest=$(jq -r '(.bg // []) | if length > 0 then (min_by(.at).at) else 0 end' "$f")
      if [ "$oldest" -gt 0 ] && [ $((now - oldest)) -gt $BG_WARN_SEC ] \
        && [ "$now" -gt "$(jq -r '.bg_snooze_until // 0' "$f")" ] && [ "$(jq -r '.bg_warned // false' "$f")" != true ]; then
        "$BOARD/bin/notify.sh" "$(jq -r .session_id "$f")" "백그라운드 작업 $(( (now - oldest) / 60 ))분째, 멈췄는지 확인해 보세요" >/dev/null 2>&1 &
        tmp=$(mktemp "$DIR/.tmp.XXXXXX")
        jq '.bg_warned = true' "$f" >"$tmp" && mv "$tmp" "$f"
      fi
    fi
  fi
  states=$(jq -c --argjson mt "$mt" --arg path "$f" --arg title "$title" --slurpfile s "$f" \
    '. + [$s[0] + {mtime: $mt, path: $path, transcript_title: $title}]' <<<"$states" 2>/dev/null || echo "$states")
done

# 앱 세션이면 앱 정보, 터미널 세션이면 터미널 표시. 둘 다 아니면(claude -p 등) null
FILTER_COMMON='
  def terminal: (.entrypoint // "") | IN("cli", "claude-vscode");
  def source($idx): . as $s | ($idx[$s.session_id]) as $m
    | if $m != null then {kind: "app", m: $m}
      elif ($s | terminal) then {kind: "terminal", m: null}
      else null end;
  def bgcount: (.bg // []) | length;
'

# 지울 것:
#  - 앱에도 터미널에도 속하지 않는 실행(claude -p 등)은 하루 뒤
#  - 보관·예약 루틴 앱 세션은 바로
#  - 터미널 세션이 완료 아닌 채로 하루 넘게 소식이 없으면 (창을 닫았거나 멈춘 것)
jq -r --slurpfile idx "$IDX" --argjson now "$(date +%s)" "$FILTER_COMMON"'
  .[] | . as $s | ($s | source($idx[0])) as $src
  | select(
      ($src == null and ($now - $s.updated_at) > 86400)
      or ($src.kind == "app" and (($src.m.archived // false) or ($src.m.scheduled // false)))
      or ($src.kind == "terminal" and $s.state != "done" and ($now - $s.mtime) > 86400))
  | .path' <<<"$states" | while IFS= read -r p; do rm -f "$p"; done

jq -c --slurpfile idx "$IDX" --argjson now "$(date +%s)" --argjson stale "$STALE_SEC" --argjson bgwarn "$BG_WARN_SEC" "$FILTER_COMMON"'
  def dur: if . < 60 then "방금" elif . < 3600 then "\(. / 60 | floor)분"
           else "\(. / 3600 | floor)시간 \((. % 3600) / 60 | floor)분" end;
  def rank: {needs_input: 0, running: 1, done: 2}[.state] // 3;

  [ .[] | . as $s | ($s | source($idx[0])) as $src
    | select($src != null)
    | select($src.kind == "terminal" or (($src.m.archived | not) and ($src.m.scheduled | not)))
    | ($now - $s.started_at) as $el | ($now - $s.mtime) as $idle
    | ($s.cwd | split("/") | last) as $folder
    | ($s | bgcount) as $bgn
    | (if $bgn > 0 then $now - ($s.bg | min_by(.at).at) else 0 end) as $bgage
    # 백그라운드 작업이 기준 시간을 넘겼고 "더 기다리기"로 미룬 시간도 지났으면 확인 필요
    | ($bgn > 0 and $bgage > $bgwarn and $now > ($s.bg_snooze_until // 0)) as $bgwarned
    # 화면에 보일 상태: 확인 필요 > 오래 걸리는 백그라운드 > 답은 끝났지만 백그라운드가 도는 중 > 원래 상태
    | (if $s.state == "needs_input" then "needs_input"
       elif $bgwarned then "needs_input"
       elif $bgn > 0 and $s.state == "done" then "running"
       else $s.state end) as $state
    | (if $bgn > 1 then "백그라운드 작업 \($bgn)개" else "백그라운드 작업" end) as $bgname
    | {
        session_id: $s.session_id,
        kind: $src.kind,
        local_id: (if $src.kind == "app" then $src.m.id else "" end),
        app_bundle: ($s.app_bundle // ""),
        title: (if $src.kind == "app" then (if ($src.m.title // "") == "" then $folder else $src.m.title end)
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
        short: (if $state == "needs_input" then (if $bgwarned and $s.state != "needs_input" then "백그라운드 \($bgage | dur)" else "확인 필요" end)
                elif $bgn > 0 and $s.state == "done" then "백그라운드 \($bgage | dur)"
                elif $state == "running" then (if $el < 60 then "방금" else ($el | dur) end)
                else "\(($now - $s.updated_at) | dur) 전" end),
        label: (
          (if $src.kind == "terminal" then "터미널 · \($folder) · " else "" end)
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
