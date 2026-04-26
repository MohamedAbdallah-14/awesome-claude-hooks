# Security Hooks

Hooks that enforce security guardrails on Claude Code's tool calls. They run inline with every tool invocation — no background process, no separate service.

> **Test in a dev environment first.** Blocking hooks that are misconfigured or too aggressive will prevent Claude from doing useful work. Audit the patterns against your codebase before enabling in production sessions.

---

## What security hooks do

Claude Code hooks are shell scripts that receive a JSON payload on stdin describing what the agent is about to do (PreToolUse) or just did (PostToolUse). PreToolUse hooks can block the action by exiting with code 2 and outputting `{"decision":"block","reason":"..."}`. PostToolUse hooks are observational — they log and alert but cannot undo actions.

These hooks address the most common ways an AI coding agent can go wrong:

- Writing plaintext credentials into source files
- Overwriting `.env` files that hold production secrets
- Modifying OS system paths outside the project
- Executing shell commands that can cause irreversible system damage
- Introducing SQL injection vectors via string concatenation
- Installing npm packages without vulnerability awareness

---

## Hook reference

| Script | Event | Blocks? | Description | Config env var |
|---|---|---|---|---|
| `block-secrets.sh` | PreToolUse | Yes | Scans file content for hardcoded API keys, tokens, passwords, and secrets before writing | `CLAUDE_ALLOW_SECRETS=1` to disable |
| `protect-dotenv.sh` | PreToolUse | Yes | Blocks any write to `.env`, `.env.*`, or `*.env` files | `CLAUDE_ALLOW_ENV_WRITES=1` to disable |
| `block-system-paths.sh` | PreToolUse | Yes | Blocks writes to `/etc`, `/usr`, `/bin`, `/sbin`, `/boot`, `/sys`, `/proc`, `/lib`; blocks shell redirects into `/etc/`, `rm -rf /`, `chmod 777 /` | `CLAUDE_ALLOWED_SYSTEM_PATHS=/path1:/path2` to whitelist specific exceptions |
| `audit-file-writes.sh` | PostToolUse | No | Logs every file write to `~/.claude/audit.log` with timestamp, session ID, path, and byte count. Rotates at 10 MB | `CLAUDE_AUDIT_LOG=/custom/path` |
| `scan-sql-injection.sh` | PreToolUse | Warn only (configurable) | Scans `.py`, `.js`, `.ts`, `.php`, `.rb`, `.java`, `.go` files for SQL string concatenation patterns. Warns to stderr by default | `CLAUDE_SQL_BLOCK=1` to make it blocking |
| `block-dangerous-bash.sh` | PreToolUse | Yes | Blocks `rm -rf /`, fork bombs, `dd` disk wipes, `mkfs`, and `curl/wget \| bash` patterns | `CLAUDE_DANGEROUS_BASH_WARN_ONLY=1` to warn instead of block |
| `audit-bash-commands.sh` | PostToolUse | No | Logs every bash command (first 200 chars) and exit code to `~/.claude/bash-audit.log`. Rotates at 10 MB | `CLAUDE_BASH_AUDIT_LOG=/custom/path` |
| `check-npm-audit.sh` | PreToolUse | Optional | Reminds you to run `npm audit` after installs. With `CLAUDE_NPM_AUDIT_BLOCK=1`: runs audit first and blocks if critical CVEs exist | `CLAUDE_NPM_AUDIT_BLOCK=1` to block on critical vulns |

---

## Sensible default setup

This `settings.json` snippet enables all security hooks with safe defaults. Replace `/path/to/hooks` with the absolute path to this directory.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/security/block-secrets.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/security/protect-dotenv.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/security/block-system-paths.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/security/scan-sql-injection.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/security/block-system-paths.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/security/block-dangerous-bash.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/security/check-npm-audit.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/security/audit-file-writes.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/security/audit-bash-commands.sh"
          }
        ]
      }
    ]
  }
}
```

Place this in `~/.claude/settings.json` for global effect, or in `.claude/settings.json` inside a specific project to limit scope.

---

## Requirements

- `jq` — all hooks require it. Install with `brew install jq` (macOS) or `apt install jq` (Debian/Ubuntu). Hooks exit cleanly with a warning if `jq` is missing, so they fail open rather than blocking all work.
- `npm` — required only by `check-npm-audit.sh` when `CLAUDE_NPM_AUDIT_BLOCK=1`.

---

## Testing a hook manually

```bash
# Simulate a Write event with a fake OpenAI key
echo '{"session_id":"test","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/test.py","content":"api_key = \"sk-aBcDeFgHiJkLmNoPqRsTuVwXyZ0123456789012345678901\""}}' \
  | bash hooks/security/block-secrets.sh
echo "Exit: $?"

# Simulate a Bash event
echo '{"session_id":"test","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
  | bash hooks/security/block-dangerous-bash.sh
echo "Exit: $?"
```

A blocking hook prints JSON to stdout and exits 2. A passing hook exits 0 with no output.

---

## Adjusting sensitivity

Hooks are intentionally conservative. If you hit false positives:

- **Secrets scanner** — set `CLAUDE_ALLOW_SECRETS=1` to disable for test fixture sessions, or extend the pattern list for domain-specific key formats.
- **SQL injection scanner** — runs warn-only by default. The pattern list covers common cases but may flag valid parameterized code that happens to look like concatenation in context. Review warnings before enabling `CLAUDE_SQL_BLOCK=1`.
- **System paths** — use `CLAUDE_ALLOWED_SYSTEM_PATHS=/etc/hosts:/usr/local` to carve out specific exceptions for legitimate sysadmin workflows.
- **Dangerous bash** — `CLAUDE_DANGEROUS_BASH_WARN_ONLY=1` is appropriate for infrastructure sessions where these commands might be intentional.
