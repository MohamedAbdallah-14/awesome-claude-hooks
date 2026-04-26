# `block-dangerous-bash`

> Source: [`hooks/security/block-dangerous-bash.sh`](../../hooks/security/block-dangerous-bash.sh)
> Event: `PreToolUse` (matcher `Bash`)
> Risk level: `blocking`
> Bypass: `CLAUDE_DANGEROUS_BASH_WARN_ONLY=1`

## Problem

Claude is good at synthesizing shell commands. It is not good at noticing when a command will erase your filesystem. A confidently-typed `rm -rf /` is the same number of tokens as a confidently-typed `rm -rf ./build`, and a model that has scanned millions of "fix the permissions" Stack Overflow threads has seen plenty of `chmod 777 /`.

This hook is a circuit breaker. It blocks the small set of commands that are catastrophic, irreversible, or remote-code-execution-shaped.

## What it catches

| Pattern | Why |
|---------|-----|
| `rm -rf /`, `rm -rf /*`, `rm -rf ~` | Whole-system / whole-home wipe. |
| Fork bomb `:(){ :|:& };:` | Locks up the machine. |
| `dd if=/dev/zero of=/dev/sd*\|hd*\|nvme*` | Disk wipe. |
| `mkfs.*` (any filesystem) | Reformats a partition. |
| `curl ... \| bash`, `wget ... \| sh` | Remote code execution from an unaudited URL. |

That's it. The hook is intentionally narrow — it isn't trying to be a full IDS, it's trying to stop the five-or-so scripts that turn a ten-minute mistake into a day-long recovery.

## Before

Claude wants to run:

```
rm -rf /
```

Without the hook, the Bash tool runs it. Goodbye system.

## After

The Bash call is intercepted. Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked: catastrophic command pattern detected (rm -rf / or variant). This was almost certainly not what you meant. Set CLAUDE_DANGEROUS_BASH_WARN_ONLY=1 to log instead of block."
  }
}
```

Claude rewrites to a scoped path. Your machine survives.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/security/block-dangerous-bash.sh"
          }
        ]
      }
    ]
  }
}
```

Or as part of the `security` profile.

## Test locally

```bash
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
  | bash hooks/security/block-dangerous-bash.sh; echo "exit: $?"
```

Expected: exit `0`, stdout JSON with `permissionDecision: deny`.

Coverage: [`tests/security/block-dangerous-bash.bats`](../../tests/security/block-dangerous-bash.bats) — 9 cases including a curl-pipe-bash test.

## Bypass

`CLAUDE_DANGEROUS_BASH_WARN_ONLY=1` flips the hook from block-mode to log-mode: it writes the warning to stderr and lets the command run. Useful only when you're deliberately testing destructive flows in a throwaway VM.

## Safety notes

- No network calls.
- Stateless — does not write logs or files of its own.
- Pattern set is hardcoded for clarity. To add a new pattern, edit the `PATTERNS` array in the script and add a bats case. The contributing guide lists the steps.
- The list does **not** include things like `git push --force` or `kubectl delete`. Those are destructive in context but not always wrong; they belong to dedicated hooks (`protect-main-branch`, `kubernetes-prod-guard`).
