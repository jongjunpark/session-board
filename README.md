# SessionBoard

[English](README.en.md)

Claude Code 세션을 여러 개 병렬로 돌리다 보면 어떤 게 돌고 있고, 어떤 게 끝났고, 어떤 게 내 답을 기다리는지 잊어버리기 쉬워요.
SessionBoard 는 그걸 화면 한쪽에 늘 떠 있는 작은 창으로 모아 보여 줘요.

- **진행중** — Claude 가 일하는 중. 몇 분째인지, 백그라운드 작업이 도는지
- **확인 필요** — 내 차례. 권한 승인, 선택지 질문, 계획 승인, 너무 오래 도는 백그라운드 작업
- **완료** — 끝났는데 아직 확인 안 함. 마지막 답의 첫 줄과 함께, **확인을 누를 때까지** 남아 있어요

Claude 데스크톱 앱(Code 탭) 세션과 터미널에서 띄운 `claude` 세션을 모두 보여 줘요.

## 설치

macOS 15 이상 (Apple Silicon·Intel). 유리 효과는 macOS 26 이상에서 보여요.

### Homebrew

```bash
brew install --cask jongjunpark/tap/session-board
```

### 직접 받기

[최신 릴리스](https://github.com/jongjunpark/session-board/releases/latest)에서 `SessionBoard.zip` 을 받아 풀고, `SessionBoard.app` 을 응용 프로그램 폴더로 옮기세요.

애플 공증을 받지 않은 자체 서명 앱이라, 처음 열 때 "확인되지 않은 개발자" 경고가 떠요. 한 번만 넘기면 돼요.

- **Finder** — `SessionBoard.app` 을 오른쪽 클릭 → **열기** → 대화상자에서 다시 **열기**
- **터미널** — `xattr -dr com.apple.quarantine /Applications/SessionBoard.app`

(Homebrew 로 설치하면 이 과정이 필요 없어요.)

### 처음 실행

앱을 처음 열면 Claude Code 설정(`~/.claude/settings.json`)에 훅을 추가할지 물어요.

- 이미 있는 다른 설정·훅은 그대로 두고, 필요한 훅만 더해요.
- 고치기 전 원본을 `settings.json.bak-session-board-<시각>` 으로 백업해요.
- 로그인할 때 자동으로 켜지게 등록해요.
- 이미 돌고 있던 세션은 **다음 요청부터** 잡혀요.

## 쓰는 법

| 동작 | 결과 |
|---|---|
| 접힌 알약에 마우스 올리기 | 한 줄짜리 짧은 목록이 펼쳐져요 |
| 알약 클릭 | 요약·버튼이 있는 큰 화면으로 고정 |
| 세션 클릭 | Claude 앱에서 그 세션 열기 (터미널 세션은 그 터미널 앱을 앞으로) |
| 완료 항목의 **확인** | 목록에서 치우기 (마우스를 올리면 보여요) |
| **더 기다리기** | 오래 도는 백그라운드 작업 알림을 15분 뒤로 미루기 |
| 위쪽 줄 오른쪽 클릭 | 완료 전부 확인 · 로그인 시 실행 · 훅 추가 · 제거 · 종료 |
| 창 끌기 | 위치를 옮겨요 (오른쪽 위 모서리 기준으로 기억) |

확인 필요가 되면 소리와 함께 알림이 떠요.

## 어떻게 동작하나요

1. Claude Code 훅이 세션에 일이 생길 때마다 `~/.claude/session-board/bin/hook.sh` 를 실행해, 세션마다 상태 파일(`~/.claude/session-board/state/*.json`)을 남겨요.
2. 앱이 3초마다 상태 파일을 모아 보여 줘요. 세션 제목은 Claude 데스크톱 앱의 세션 정보에서, 터미널 세션은 대화 기록의 제목(`/rename` 또는 자동 제목)에서 가져와요.
3. 백그라운드 작업은 시작을 기록해 두고, 대화 기록에 완료 알림이 오면 빼요. 15분 넘게 돌면 확인 필요로 올려요.

외부로 보내는 데이터는 없어요. 전부 이 맥 안의 파일만 읽고 써요.

## 알려진 한계

- 세션 제목·앱 세션 판별은 Claude 데스크톱 앱이 내부적으로 저장하는 파일을 읽어요. 공개 규격이 아니라서 **앱 업데이트로 깨질 수 있어요.**
- 도중에 멈춤을 누르면 끝났다는 신호가 오지 않아 진행중으로 남아요. 10분 넘게 움직임이 없으면 "소식 없음"이 붙어요.
- Claude 가 글로 되묻고 끝나면(선택지 창 없이) 확인 필요가 아니라 완료로 떠요.
- 터미널 세션은 여러 탭 중 정확한 탭으로 이동하지 못하고, 터미널 앱만 앞으로 가져와요.

## 제거

- 앱에서: 위쪽 줄 오른쪽 클릭 → **세션 보드 제거…** (훅·자동 실행·기록을 모두 걷어내요). 그다음 앱을 휴지통으로.
- Homebrew: `brew uninstall --zap --cask session-board`

## 직접 빌드

```bash
swift build                     # 디버그 빌드
./scripts/build-app.sh          # build/SessionBoard.app
./scripts/build-app.sh --install  # /Applications 에 설치하고 실행
```

메뉴 막대에도 띄우고 싶다면 [SwiftBar](https://swiftbar.app) 플러그인 `extras/swiftbar/session-board.5s.sh` 를 쓸 수 있어요.

## 라이선스

[MIT](LICENSE)
