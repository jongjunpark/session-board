# SessionBoard

[한국어](README.md)

When you run several Claude Code sessions in parallel, it's easy to lose track of which ones are working, which ones finished, and which ones are waiting on you.
SessionBoard keeps a small floating board on your screen that shows exactly that.

- **Running** — Claude is working. Shows how long, and whether background tasks are still going
- **Needs you** — your turn: a permission prompt, a multiple-choice question, plan approval, or a background task that has been running too long
- **Done** — finished but not yet acknowledged. Shows the first line of the last reply and **stays until you confirm it**

It covers both Claude desktop app (Code tab) sessions and `claude` sessions started from a terminal.

> The UI is in Korean for now.

## Install

macOS 15 or later (Apple Silicon or Intel). The Liquid Glass look needs macOS 26.

### Homebrew

```bash
brew install --cask jongjunpark/tap/session-board
```

### Manual

Download `SessionBoard.zip` from the [latest release](https://github.com/jongjunpark/session-board/releases/latest), unzip it, and move `SessionBoard.app` to `/Applications`.

The app is ad-hoc signed (not notarized), so Gatekeeper warns about an unidentified developer on first launch. Clear it once:

- **Finder:** right-click `SessionBoard.app` → **Open** → **Open** again
- **Terminal:** `xattr -dr com.apple.quarantine /Applications/SessionBoard.app`

(The Homebrew cask does this for you.)

### First launch

On first launch the app asks to add hooks to Claude Code's settings (`~/.claude/settings.json`).

- Your existing settings and hooks are left untouched; only the missing hooks are added.
- The original file is backed up as `settings.json.bak-session-board-<timestamp>`.
- The app registers itself to open at login.
- Sessions that are already running are picked up from their **next** prompt.

## How it works

1. Claude Code hooks run `~/.claude/session-board/bin/hook.sh` on session events and keep one state file per session in `~/.claude/session-board/state/`.
2. The app reads those files every 3 seconds. Titles come from the Claude desktop app's session data, or from the transcript title (`/rename` or the auto title) for terminal sessions.
3. Background tasks are recorded when started and removed when their completion notice shows up in the transcript. After 15 minutes they are flagged as needing you.

Nothing leaves your Mac — it only reads and writes local files.

## Known limitations

- Session titles and app-session detection read the Claude desktop app's internal session files. That format is not public and **may break with app updates.**
- If you interrupt a session, no "stopped" signal arrives, so it stays running; after 10 idle minutes it is marked as quiet.
- If Claude ends a turn by asking a question in plain text (no choice dialog), it shows up as done, not as needing you.
- Terminal sessions can't jump to the exact tab; the terminal app is brought to the front instead.

## Uninstall

- In the app: right-click the header → **세션 보드 제거…** (removes hooks, login item and state), then move the app to the Trash.
- Homebrew: `brew uninstall --zap --cask session-board`

## Build from source

```bash
swift build
./scripts/build-app.sh            # build/SessionBoard.app
./scripts/build-app.sh --install  # copy to /Applications and launch
```

A [SwiftBar](https://swiftbar.app) menu bar plugin is in `extras/swiftbar/`.

## License

[MIT](LICENSE)
