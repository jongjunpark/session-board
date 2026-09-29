# SessionBoard

[한국어](README.md)

When you run several Claude Code sessions at once, it's easy to lose track of which ones are still working, which ones have finished, and which ones are waiting for you.
SessionBoard shows the state of every session at a glance, in a small floating window and in the menu bar.

- **Running**: Claude is working. Shows how long, and whether background tasks are still going.
- **Needs you**: it's your turn — a permission prompt, a multiple-choice question, plan approval, or a background task that has been running too long.
- **Done**: finished. Shows the first line of the last reply and **stays until you confirm it**.

It covers both Claude desktop app (Code tab) sessions and `claude` sessions started from a terminal.

> The UI is in Korean for now.

## Install

macOS 15 or later (Apple Silicon or Intel). The Liquid Glass UI needs macOS 26.

### Homebrew

```bash
brew install --cask jongjunpark/tap/session-board
```

### Manual

Download `SessionBoard.zip` from the [latest release](https://github.com/jongjunpark/session-board/releases/latest), unzip it, and move `SessionBoard.app` to `/Applications`.

The app is not notarized, so Gatekeeper warns about an unidentified developer on first launch. Open it once in one of these ways and it opens normally afterwards:

- **Finder:** right-click `SessionBoard.app` → **Open** → **Open** again
- **Terminal:** `xattr -dr com.apple.quarantine /Applications/SessionBoard.app`

The Homebrew cask does this for you.

### First launch

On first launch the app asks to add hooks to Claude Code's settings file (`~/.claude/settings.json`).

- Your existing settings and hooks are left as they are; only the missing hooks are added.
- The original file is backed up as `settings.json.bak-session-board-<timestamp>`.
- The app registers itself to open at login.
- Sessions that are already running show up from their **next** prompt.

## Usage

Most of the time the window stays collapsed and only shows counts.

| Do this | What happens |
|---|---|
| Hover over the collapsed window | A compact one-line-per-session list unfolds |
| Click the collapsed window | Opens the full window with summaries and buttons |
| Click a session | Opens it in the Claude app (terminal sessions bring their terminal app forward) |
| **확인** (Confirm) on a done session | Removes it from the list (appears on hover) |
| **더 기다리기** (Wait longer) | Postpones the long-running background task alert by the configured time |
| Right-click the top of the window | Confirm all done, refresh, settings, quit |
| Drag the window | Move it anywhere; the position is remembered |

You get a notification with a sound when a session needs you.

### Menu bar

The menu bar shows `● needs you  ⟳ running  ✓ done` counts too. Click it for the session list, where you can open, confirm or postpone each session. You can hide the floating window and use only the menu bar (menu bar → **떠 있는 창 보이기/숨기기**, show/hide floating window).

## Settings

Right-click the top of the window → **설정…** (Settings).

- **General:** open at login, show in menu bar
- **Background tasks:** alert when they run long (on/off), threshold (5, 10, 15, 20, 30 minutes or 1 hour; default 15 minutes)
- **Updates:** update notifications (on/off), check now
- **Manage:** add or remove the Claude Code hooks, uninstall SessionBoard

## Updates

With update notifications on, the app checks for a new version at launch and every 6 hours. When one is available, a **new version** badge appears at the top of the window; click it to update.

- Manual installs: the app downloads the new version, verifies the file against the release checksum, swaps it in and relaunches.
- Homebrew installs: the app runs `brew upgrade` and relaunches.

You can also run `/Applications/SessionBoard.app/Contents/MacOS/SessionBoard --self-update` to update from a terminal.

## How it works

1. On every session event, Claude Code hooks run `~/.claude/session-board/bin/hook.sh`, which keeps one state file per session in `~/.claude/session-board/state/`.
2. The app reads those files every 3 seconds. Titles come from the Claude desktop app's session data, or, for terminal sessions, from the title stored in the transcript (`/rename` or the automatic title).
3. Background tasks are recorded when they start and removed when their completion notice appears in the transcript.

Apart from checking GitHub for updates, nothing leaves your Mac — everything is stored locally.

## Good to know

- Session titles and app-session detection read files the Claude desktop app keeps internally. That format is not public, so **an app update may break it.**
- If you interrupt a session, no "stopped" signal arrives, so it stays running; after 10 minutes without activity it is marked as quiet.
- If Claude ends a turn by asking a question in plain text (no choice dialog), it shows as done, not as needing you.
- Clicking a terminal session brings the terminal app forward but can't switch to the exact tab.

## Uninstall

- **In the app:** right-click the top of the window → **설정…** → **세션 보드 제거** (removes the hooks, login item and records), then move the app to the Trash.
- **Homebrew:** `brew uninstall --zap --cask session-board`

## Build from source

```bash
swift build                       # debug build
./scripts/build-app.sh            # build/SessionBoard.app
./scripts/build-app.sh --install  # copy to /Applications and launch
```

## License

[MIT](LICENSE)
