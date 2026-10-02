# Approving Codex hooks

[한국어](codex-hooks.md) · [Back to README](../README.en.md#claude-code-and-codex-hooks-and-approval)

To know the state of Codex sessions, SessionBoard adds **6 hooks** to Codex's settings (`~/.codex/hooks.json`).
For security, Codex runs **new or changed hooks only after you trust them**. Until then, Codex sessions don't appear in SessionBoard.

Approving once covers **both the Codex app and the CLI** — do it in whichever is handier.

> The screenshots show the Korean UI; the steps are the same in other languages.

## In the Codex app

**1.** Click the **hook icon** below the composer. It has a yellow dot when there are hooks to review.

<p align="center"><img src="images/codex-hook-icon.png" alt="Hook icon with a yellow dot in the Codex app composer" width="360"></p>

**2.** The hook review dialog lists the 6 SessionBoard hooks as **new**. Click **Allow all** (모두 허용).

<p align="center"><img src="images/codex-hook-review.png" alt="Hook review dialog listing hooks 1–6 as new, with the Allow all button" width="620"></p>

## In the Codex CLI

Running `codex` shows "Hooks need review". Choose **2. Trust all and continue**.

<p align="center"><img src="images/codex-hook-cli.png" alt="Codex CLI Hooks need review prompt with Trust all and continue selected" width="560"></p>

If you choose `3. Continue without trusting`, the hooks won't run and Codex sessions won't be listed. You can review them later with `/hooks`.

## Good to know

- **Updating SessionBoard usually doesn't require approving again.** Codex remembers trust per hook definition in `hooks.json` (command, event, matcher). You only need to approve again when an update changes those definitions, and the app tells you first.
- Trust is stored in `[hooks.state]` in `~/.codex/config.toml`. SessionBoard never writes trust records for you — that would bypass Codex's security review.
- The hooks only write session state files to `~/.claude/session-board/state/` (plus the last 500 received event types in `events.log`, for troubleshooting) and show a notification when you're needed. They never change a session, never approve anything for you, and send nothing off your Mac.
- See the connection state and connect/disconnect under **설정… → 관리 → Codex 연동** (Settings → Manage → Codex).
