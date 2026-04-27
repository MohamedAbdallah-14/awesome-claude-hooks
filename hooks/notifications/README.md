# Notification hooks

Hooks that fire when Claude finishes a task so you can step away from the terminal: cross-platform desktop banners, sounds, terminal-title updates, and bridges to Slack, Telegram, Discord, and Pushover. Pick one or layer several.

The webhook-based hooks (`slack-notify`, `telegram-notify`, `discord-notify`, `pushover-notify`) require credentials in environment variables. See each hook's header for the variable names.

## Hooks

- [`desktop-notify`](desktop-notify.sh) ([catalog](../../docs/hooks.md#notifications)) — Cross-platform desktop banner. Picks `osascript` (macOS), `notify-send` (Linux), or PowerShell (WSL).
- [`macos-notify`](macos-notify.sh) ([catalog](../../docs/hooks.md#notifications)) — macOS-only banner via `osascript`. Falls back silently elsewhere.
- [`linux-notify`](linux-notify.sh) ([catalog](../../docs/hooks.md#notifications)) — Linux-only banner via `notify-send`.
- [`slack-notify`](slack-notify.sh) ([catalog](../../docs/hooks.md#notifications)) — Posts to a Slack Incoming Webhook with session ID, timestamp, and cwd.
- [`telegram-notify`](telegram-notify.sh) ([catalog](../../docs/hooks.md#notifications)) — Sends a Telegram message via the Bot API.
- [`discord-notify`](discord-notify.sh) ([catalog](../../docs/hooks.md#notifications)) — Posts a Discord embed via webhook.
- [`pushover-notify`](pushover-notify.sh) ([catalog](../../docs/hooks.md#notifications)) — Sends a push notification to iOS or Android via the Pushover API.
- [`sound-complete`](sound-complete.sh) ([catalog](../../docs/hooks.md#notifications)) — Plays a chime on `Stop`. macOS uses `afplay`, Linux tries `paplay` then `aplay`.
- [`sound-error`](sound-error.sh) ([catalog](../../docs/hooks.md#notifications)) — Plays an error sound when a tool exits non-zero or its stderr contains "Error".
- [`terminal-title`](terminal-title.sh) ([catalog](../../docs/hooks.md#notifications)) — Updates the terminal/tab title to show the running tool. Works in iTerm2, Terminal.app, tmux, xterm.

## Install just this category

The `notifications` profile installs every hook here:

```bash
bash scripts/install.sh --profile=notifications --global
```

Or use the category flag:

```bash
bash scripts/install.sh --category=notifications --global
```

Most users want only `desktop-notify` plus one of the chat bridges. Edit `~/.claude/settings.json` after install to remove the rest.
