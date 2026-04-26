# Getting Started

Claude Code hooks are shell scripts that run at specific points in Claude's execution cycle — before a tool call, after it completes, when the session ends. They let you enforce rules, inject context, trigger notifications, and run side effects without modifying Claude's core behavior. The hooks in this repo are production-ready scripts you drop in and wire up; no build step, no dependencies beyond bash and jq.

## Prerequisites

- **Bash 4+** — macOS ships with Bash 3.2 (check with `bash --version`). Either install Bash 5 via Homebrew (`brew install bash`) or ensure scripts use `#!/usr/bin/env bash` with POSIX-compatible syntax.
- **jq** — JSON processor used by most hooks. Install: `brew install jq` / `apt install jq` / `pacman -S jq`
- **Claude Code CLI** — [Install instructions](https://docs.anthropic.com/claude-code)

## Installation Methods

### Method A: Manual (single hook)

Copy the hook script you want somewhere stable, then add it to `settings.json`.

```bash
mkdir -p ~/.claude/hooks
cp hooks/notifications/sound-complete.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/sound-complete.sh
```

Then add the hook to your settings (see [Basic settings.json hook structure](#basic-settingsjson-hook-structure) below).

### Method B: Clone the repo (recommended for multiple hooks)

```bash
git clone https://github.com/your-org/awesome-claude-hooks ~/.claude/hooks-lib
```

Reference scripts by absolute path in your `settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash ~/.claude/hooks-lib/hooks/notifications/sound-complete.sh"
          }
        ]
      }
    ]
  }
}
```

Update the library later with `git -C ~/.claude/hooks-lib pull`.

### Method C: Quick fetch (single hook, no clone)

```bash
curl -fsSL https://raw.githubusercontent.com/your-org/awesome-claude-hooks/main/hooks/notifications/sound-complete.sh \
  -o ~/.claude/hooks/sound-complete.sh
chmod +x ~/.claude/hooks/sound-complete.sh
```

## Settings.json Locations

| File | Scope |
|------|-------|
| `~/.claude/settings.json` | Global — applies to every Claude Code session |
| `.claude/settings.json` | Project-local — applies only when Claude runs in that directory |

Project-local settings merge with global settings. Hook lists concatenate; other keys follow last-writer-wins.

## Basic settings.json Hook Structure

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/hooks/security/block-secrets.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/hooks/quality/eslint-gate.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/hooks/notifications/sound-complete.sh"
          }
        ]
      }
    ]
  }
}
```

**`matcher`** is a regex matched against the tool name. Omit it (or set `""`) to match all tools. `"Bash"` matches only Bash calls. `"Write|Edit"` matches Write or Edit.

**`type`** is always `"command"` for shell hooks.

**`command`** is executed as a shell command. The hook receives event JSON on stdin.

## Testing a Hook

Pipe a synthetic event JSON directly to the script. The exact shape depends on the event type, but for a `Stop` event:

```bash
echo '{"hook_event_name":"Stop","session_id":"test-123","transcript_path":"/tmp/test"}' \
  | bash hooks/notifications/sound-complete.sh
```

For a `PreToolUse` event targeting Bash:

```bash
echo '{
  "hook_event_name": "PreToolUse",
  "session_id": "test-123",
  "tool_name": "Bash",
  "tool_input": {"command": "rm -rf /tmp/test"},
  "transcript_path": "/tmp/test"
}' | bash hooks/security/bash-guard.sh
```

A well-written hook exits 0 for allow, 2 for block, and prints a JSON decision object to stdout when blocking.

## Debugging

Set `CLAUDE_DEBUG=1` before running a hook to enable verbose output in hooks that respect it:

```bash
CLAUDE_DEBUG=1 echo '{"hook_event_name":"Stop","session_id":"test"}' \
  | bash hooks/notifications/sound-complete.sh
```

Hooks in this repo write debug info to **stderr** (not stdout), so it won't interfere with Claude's JSON parsing of the response. When hooks fire inside Claude Code itself, stderr output appears in the terminal where Claude is running.

To see what Claude Code is passing to your hooks, add a quick logger:

```bash
# Prepend to any hook for temporary debugging
tee /tmp/hook-input-$(date +%s).json >&2
```

## Troubleshooting

**Hook not firing**

- Check event name spelling: `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `PreCompact` — case-sensitive.
- Check your `matcher` regex. `"bash"` (lowercase) won't match `"Bash"`. Test with: `echo "Bash" | grep -E "bash"` vs `"Bash"`.
- Confirm the hook entry is under the correct event key in `settings.json`.
- Validate your JSON: `jq . ~/.claude/settings.json` — a syntax error silently disables all hooks.

**Permission denied**

```bash
chmod +x /path/to/your-hook.sh
```

**jq: command not found**

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install -y jq

# Arch
sudo pacman -S jq

# Alpine
apk add jq
```

**Hook fires but does nothing**

Check that the script path in `settings.json` is absolute, not relative. Claude Code's working directory when running hooks may not be what you expect. Always use `~` or full paths.
