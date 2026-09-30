# SessionBoard

[한국어](README.md)

When you run several Claude Code or Codex sessions at once, it's easy to lose track of which ones are still working, which ones have finished, and which ones are waiting for you.
SessionBoard shows the state of every session at a glance, in a small floating window and in the menu bar.

- **Running**: Claude or Codex is working. Shows how long, and whether background tasks are still going.
- **Needs you**: it's your turn — a permission prompt, a multiple-choice question, plan approval, or a background task that has been running too long.
- **Done**: finished. Shows the first line of the last reply and **stays until you confirm it**.

It covers Claude desktop app (Code tab) sessions, `claude` sessions started from a terminal, and Codex (app and CLI) sessions. A symbol before each title tells the tools apart: **Claude is an orange ✳, Codex is `>_`**.

<p align="center"><img src="docs/images/overview.webp" alt="Session states in the floating window and the menu bar" width="820"></p>

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

On first launch the app asks to add hooks to Claude Code's settings file (`~/.claude/settings.json`), and to Codex's (`~/.codex/hooks.json`) if you use Codex.

- Your existing settings and hooks are left as they are; only the missing hooks are added.
- The original file is backed up as `settings.json.bak-session-board-<timestamp>`.
- The app registers itself to open at login.
- Sessions that are already running show up from their **next** prompt.
- **Codex runs new hooks only after you trust them.** Approve them with the hook icon (yellow dot) in the Codex app composer, or "Trust all and continue" in the CLI. See [Claude Code and Codex hooks and approval](#claude-code-and-codex-hooks-and-approval).

## Usage

Most of the time the window stays collapsed and only shows counts.

| Collapsed | On hover | On click |
|:---:|:---:|:---:|
| <img src="docs/images/collapsed.png" alt="Collapsed window showing only counts" width="200"> | <img src="docs/images/peek.png" alt="Compact one-line-per-session list" width="260"> | <img src="docs/images/board.webp" alt="Full window with summaries and buttons" width="300"> |

| Do this | What happens |
|---|---|
| Hover over the collapsed window | A compact one-line-per-session list unfolds |
| Click the collapsed window | Opens the full window with summaries and buttons |
| Click a session | Opens it in the Claude or Codex app (sessions started in a terminal bring that terminal app forward) |
| **확인** (Confirm) on a done session | Removes it from the list (appears on hover) |
| **더 기다리기** (Wait longer) | Postpones the long-running background task alert by the configured time |
| Right-click the top of the window | Confirm all done, refresh, settings, quit |
| Drag the window | Move it anywhere; the position is remembered |

You get a notification with a sound when a session needs you.

### Menu bar

<p align="center"><img src="docs/images/menubar.webp" alt="Session list opened from the menu bar" width="560"></p>

The menu bar shows `● needs you  ⟳ running  ✓ done` counts too. Click it for the session list, where you can open, confirm or postpone each session. You can hide the floating window and use only the menu bar (menu bar → **플로팅 창 보기/숨기기**, show/hide floating window).

## Settings

Right-click the top of the window → **설정…** (Settings).

- **General:** open at login, show in menu bar
- **Background tasks:** alert when they run long (on/off), threshold (5, 10, 15, 20, 30 minutes or 1 hour; default 15 minutes). Applies to Claude Code background tasks and to Codex commands still running after the turn ends
- **Updates:** update notifications (on/off), check now
- **Manage:** connect or disconnect Claude Code and Codex, delete SessionBoard

## Updates

With update notifications on, the app checks for a new version at launch and every 6 hours. When one is available, a **new version** badge appears at the top of the window; click it to update.

- Manual installs: the app downloads the new version, verifies the file against the release checksum, swaps it in and relaunches.
- Homebrew installs: the app runs `brew upgrade` and relaunches.

You can also run `/Applications/SessionBoard.app/Contents/MacOS/SessionBoard --self-update` to update from a terminal.

## Claude Code and Codex hooks and approval

To know each session's state, SessionBoard adds **hooks** to Claude Code and Codex. A hook is a small command the tool runs for you when something happens in a session (a prompt is sent, a tool runs, it waits for approval, it finishes, …).

### Hooks it adds

| Tool | Settings file | Command |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | `~/.claude/session-board/bin/hook.sh` |
| Codex | `~/.codex/hooks.json` | `~/.claude/session-board/bin/hook.sh --agent codex` |

- Existing settings and hooks are left as they are; only the missing hooks are added. The original file is backed up next to it as `.bak-session-board-<timestamp>`.
- The hook only writes session state files to `~/.claude/session-board/state/` and shows a notification when you're needed. It never changes a session, never approves anything for you, and sends nothing off your Mac.

### How approval differs

**Claude Code** runs hooks as soon as they're in the settings file — no approval step. (Sessions that are already running are picked up from their next prompt.)

**Codex**, for security, runs **new or changed hooks only after you trust them**. Untrusted hooks are skipped silently, so Codex sessions don't appear until you approve.

- Step-by-step with screenshots: [Approving Codex hooks](docs/codex-hooks.en.md).
- **Codex app:** click the **hook icon (with a yellow dot)** on the right of the composer and approve the SessionBoard hooks.
- **Codex CLI:** choose **Trust all and continue** in the "Review hooks" prompt at startup, or review them with `/hooks`.
- **Approving once covers both the app and the CLI.** Trust is stored in `[hooks.state]` in `~/.codex/config.toml`.
- **Updating SessionBoard does not require approving again.** Codex remembers trust per hook definition in `hooks.json`, and SessionBoard doesn't change those definitions on update. (Changes to the hook script's contents don't matter.)
- SessionBoard never writes trust records for you — that would bypass Codex's security review, so approval is always yours.

### Check or turn off

- See the connection state and connect/disconnect under **설정… → 관리 → Claude Code 연동 / Codex 연동** (Settings → Manage).
- Disconnecting removes only the SessionBoard hooks from that settings file. Codex's trust records (`[hooks.state]`) are managed by Codex and may remain.

## How it works

1. On every session event, Claude Code and Codex hooks run `~/.claude/session-board/bin/hook.sh`, which keeps one state file per session in `~/.claude/session-board/state/`.
2. The app reads those files every 3 seconds. Titles come from the Claude desktop app's session data, from the transcript title for terminal sessions (`/rename` or the automatic title), or from Codex's saved thread title.
3. Claude Code background tasks are recorded when they start and removed when their completion notice appears in the transcript. For Codex, each command is recorded when it starts and removed when it finishes; only commands still running after the turn ends are shown as background tasks.

Apart from checking GitHub for updates, nothing leaves your Mac — everything is stored locally.

## Good to know

- Session titles and app-session detection read files the Claude desktop app and Codex keep internally. That format is not public, so **an app update may break it.**
- Background runs such as `claude -p` and `codex exec` are not listed.
- If you interrupt a Claude session, no "stopped" signal arrives, so it stays running (Codex shows "interrupted" right away); after 10 minutes without activity it is marked as quiet.
- If Claude ends a turn by asking a question in plain text (no choice dialog), it shows as done, not as needing you.
- Clicking a terminal session brings the terminal app forward but can't switch to the exact tab.

- Codex exposes fewer hook signals than Claude Code, so these cases are **not** detected as needing you:
  - waiting for approval of a plan (the turn ends, so it shows as done)
  - an MCP server asking for input or sign-in
  - scheduled (automation) runs can't be told apart and are listed like other sessions
  - fully detached processes (`cmd &`) can't be tracked to completion

## Uninstall

- **In the app:** right-click the top of the window → **설정…** → **SessionBoard 삭제** (disconnects Claude Code and Codex, removes the login item and records), then move the app to the Trash.
- **Homebrew:** `brew uninstall --zap --cask session-board`

## Build from source

```bash
swift build                       # debug build
./scripts/build-app.sh            # build/SessionBoard.app
./scripts/build-app.sh --install  # copy to /Applications and launch
```

## License

[MIT](LICENSE)
