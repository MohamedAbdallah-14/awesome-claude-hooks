# `block-system-paths`

> Source: [`hooks/security/block-system-paths.sh`](../../hooks/security/block-system-paths.sh)
> Event: `PreToolUse` (matcher `Write|Edit|Bash`)
> Risk level: `blocking`
> Bypass: `CLAUDE_ALLOWED_SYSTEM_PATHS` (colon-separated path-prefix allowlist)

## Problem

Claude is "fixing" your shell PATH and decides the cleanest way is to write a new `/etc/paths` file. Or it's resolving a permissions issue and reaches for `chmod 777 /`. Or it's clearing a build cache and pipes into `rm -rf /`. Each of these is one edit away from an unbootable laptop.

This hook denies file writes under OS-managed prefixes and blocks the bash patterns that wreck a system in one command.

## What it catches

File writes (Write/Edit/MultiEdit) under any of:

| Prefix | Why |
|--------|-----|
| `/etc` | System config |
| `/usr` | Vendor binaries and libs |
| `/bin`, `/sbin` | Core executables |
| `/boot` | Boot loader |
| `/sys`, `/proc` | Kernel interfaces |
| `/lib`, `/lib64` | Shared libraries |

Bash commands matching:

| Pattern | Example |
|---------|---------|
| Redirect into `/etc/` | `echo nameserver 8.8.8.8 > /etc/resolv.conf` |
| `rm -rf /` (and `rm -rf /*`, `rm -rf "/"` variants) | `rm -rf /` |
| `rm -rf <root> $` at end of line | `sudo rm -rf /` |
| `chmod 777 /` (or with non-alnum suffix) | `chmod -R 777 /` |

## Before

Claude wants to run:

```
chmod 777 /
```

Or write to:

```
/etc/hosts
```

Without the hook, the system is one tool-call away from "you cannot log in".

## After

The action is intercepted. For the file write, Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked: write to system path '/etc/hosts' is not allowed. System paths under /etc are protected. Add the path to CLAUDE_ALLOWED_SYSTEM_PATHS to permit specific exceptions."
  }
}
```

For the bash command:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked: command attempts to set world-writable permissions on the filesystem root (chmod 777 /). This is a critical security violation."
  }
}
```

Claude reroutes the work to a user-owned location.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/security/block-system-paths.sh"
          }
        ]
      }
    ]
  }
}
```

Or as part of the `security` profile:

```bash
bash scripts/install.sh --profile=security --global
```

## Test locally

```bash
# Blocked file write
echo '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/etc/hosts","content":"127.0.0.1 evil"}}' \
  | bash hooks/security/block-system-paths.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`, reason mentions `/etc`.

```bash
# Blocked bash command
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"chmod 777 /"}}' \
  | bash hooks/security/block-system-paths.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

```bash
# Allowed via exception list
echo '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/etc/hosts","content":"..."}}' \
  | CLAUDE_ALLOWED_SYSTEM_PATHS=/etc/hosts bash hooks/security/block-system-paths.sh; echo "exit: $?"
```

Expected: exit `0`, no JSON output.

The repo's bats suite covers this hook in [`tests/security/block-system-paths.bats`](../../tests/security/block-system-paths.bats).

## Bypass

`CLAUDE_ALLOWED_SYSTEM_PATHS` is a colon-separated allowlist of path prefixes that bypass the file-write block. Example:

```bash
CLAUDE_ALLOWED_SYSTEM_PATHS=/etc/hosts:/usr/local
```

Use it for the narrowest path you actually need. `/etc` is too broad; `/etc/hosts` is fine. The bash-command rules (rm -rf /, chmod 777 /, redirect into /etc) have no bypass — there is no legitimate Claude-driven case for them.

Unset the variable when done. Leaving it set means the next session inherits the exception.

## Safety notes

- No network calls.
- Reads stdin only; does not write to disk.
- File-path normalization uses `python3` if available; falls back to the raw path. Symlinks pointing into a blocked prefix may slip through if `python3` is missing — uncommon on macOS or modern Linux.
- The bash-pattern matcher is regex-based. It is intentionally conservative: it catches the obvious destructive forms, not every creative variation. Pair with [`block-dangerous-bash`](../../hooks/security/block-dangerous-bash.sh) for broader command-level coverage.
