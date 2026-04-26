# Notification Hooks

Hooks that fire when Claude Code finishes a task (Stop event) or when a tool is called (PreToolUse / PostToolUse), keeping you informed without having to watch the terminal.

## When hooks fire

| Hook event | When |
|---|---|
| `PreToolUse` | Just before Claude calls a tool (Bash, Edit, Read, etc.) |
| `PostToolUse` | Immediately after a tool returns |
| `Stop` | When Claude finishes responding and the session goes idle |

All hooks in this directory are passive — they exit 0 and never block Claude.

---

## Hooks

| Script | Event | Description | Requires |
|---|---|---|---|
| `macos-notify.sh` | Stop | macOS notification banner via `osascript` | macOS, `jq` |
| `linux-notify.sh` | Stop | Linux desktop notification via `notify-send` | Linux, `notify-send`, `jq` |
| `slack-notify.sh` | Stop | Slack message with session info + working dir | `curl`, `jq`, Slack webhook URL |
| `discord-notify.sh` | Stop | Discord embed with session info + working dir | `curl`, `jq`, Discord webhook URL |
| `sound-complete.sh` | Stop | Plays a completion chime | macOS: built-in; Linux: `paplay` or `aplay` |
| `sound-error.sh` | PostToolUse | Plays an error sound on non-zero exit or stderr "Error" | macOS: built-in; Linux: `paplay` or `aplay`, `jq` |
| `pushover-notify.sh` | Stop | Pushover push notification (iOS / Android) | `curl`, `jq`, Pushover account |
| `telegram-notify.sh` | Stop | Telegram message via Bot API | `curl`, `jq`, Telegram bot |
| `terminal-title.sh` | PreToolUse + Stop | Updates terminal window title with live status | `jq` (optional); works in tmux, iTerm2, xterm |

---

## Configuration

Each hook is controlled by environment variables. Set them in your shell profile (`~/.zshrc`, `~/.bashrc`) or pass them in the hook command via `env VAR=value /path/to/hook.sh`.

| Variable | Hook | Required | Default | Notes |
|---|---|---|---|---|
| `CLAUDE_NOTIFY_SOUND` | `macos-notify` | No | _(no sound)_ | e.g. `"Glass"`, `"Ping"`, `"Basso"` |
| `CLAUDE_NOTIFY_URGENCY` | `linux-notify` | No | `normal` | `low` / `normal` / `critical` |
| `CLAUDE_SLACK_WEBHOOK` | `slack-notify` | Yes | — | Incoming webhook URL |
| `CLAUDE_SLACK_CHANNEL` | `slack-notify` | No | webhook default | e.g. `"#dev-alerts"` |
| `CLAUDE_SLACK_USERNAME` | `slack-notify` | No | `Claude Code` | Display name |
| `CLAUDE_DISCORD_WEBHOOK` | `discord-notify` | Yes | — | Discord channel webhook URL |
| `CLAUDE_SOUND_COMPLETE` | `sound-complete` | No | platform default | Path to any audio file |
| `CLAUDE_SOUND_ERROR` | `sound-error` | No | platform default | Path to any audio file |
| `CLAUDE_PUSHOVER_TOKEN` | `pushover-notify` | Yes | — | App token from pushover.net |
| `CLAUDE_PUSHOVER_USER` | `pushover-notify` | Yes | — | User key from pushover.net |
| `CLAUDE_PUSHOVER_PRIORITY` | `pushover-notify` | No | `0` | `-2` to `1` (emergency/2 not supported) |
| `CLAUDE_TELEGRAM_BOT_TOKEN` | `telegram-notify` | Yes | — | Token from @BotFather |
| `CLAUDE_TELEGRAM_CHAT_ID` | `telegram-notify` | Yes | — | Your chat ID |

---

## Installation

### Install all notification hooks at once

Add this block to `~/.claude/settings.json` (global) or your project's `.claude/settings.json`. Replace `/path/to/hooks` with the actual path to this directory.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/notifications/terminal-title.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/notifications/sound-error.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/notifications/terminal-title.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/notifications/sound-complete.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/notifications/macos-notify.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/notifications/linux-notify.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/notifications/slack-notify.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/notifications/discord-notify.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/notifications/pushover-notify.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/notifications/telegram-notify.sh"
          }
        ]
      }
    ]
  }
}
```

> All hooks check for their required tools and env vars at runtime and exit 0 with a warning if anything is missing. Installing the full set is safe — hooks that aren't configured simply do nothing.

### Make scripts executable

```bash
chmod +x /path/to/hooks/notifications/*.sh
```

### Pick only what you need

You don't have to install the full block. Copy just the entries you want. For example, macOS users who only want a sound and a notification banner need only `sound-complete.sh` and `macos-notify.sh` in the `Stop` array.

---

## Combining hooks

Multiple hooks in the same event array run sequentially. If you want both a sound and a Slack message when Claude finishes, add both scripts to the `Stop` array — they will both execute.

---

## Troubleshooting

**Hook silently does nothing**
Run the script manually with a test payload to see its output:
```bash
echo '{"session_id":"test-abc123","hook_event_name":"Stop","stop_hook_active":true}' \
  | bash /path/to/hooks/notifications/macos-notify.sh
```

**`jq: command not found`**
Install jq:
- macOS: `brew install jq`
- Ubuntu/Debian: `sudo apt install jq`
- Fedora: `sudo dnf install jq`

**`notify-send` not found on Linux**
Install libnotify: `sudo apt install libnotify-bin`

**Slack/Discord returns non-200**
Check that your webhook URL is correct and the app still has permission to post to the channel.

**Terminal title not updating in tmux**
The hook uses `tmux rename-window` when `$TMUX` is set. Ensure your tmux version is ≥ 1.8. If you prefer not to rename windows, remove or skip `terminal-title.sh`.
