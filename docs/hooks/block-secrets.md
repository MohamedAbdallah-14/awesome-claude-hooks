# `block-secrets`

> Source: [`hooks/security/block-secrets.sh`](../../hooks/security/block-secrets.sh)
> Event: `PreToolUse` (matcher `Write|Edit|MultiEdit`)
> Risk level: `blocking`
> Bypass: `CLAUDE_ALLOW_SECRETS=1`

## Problem

Claude can paste credentials directly into source files when summarizing test fixtures, copying examples from logs, or finishing a half-written config. Once a key lands in git, the surface area is the entire history of every clone — even after a force-push and a key rotation, somebody, somewhere, has a copy.

This hook stops the write before it happens.

## What it catches

| Pattern | Example |
|---------|---------|
| OpenAI API key | `sk-` followed by 48 alphanumerics |
| AWS Access Key ID | `AKIA` followed by 16 uppercase/digit chars |
| GitHub personal access token | `ghp_` followed by 36 alphanumerics |
| Slack bot token | `xoxb-` followed by 51 alphanumeric/dash chars |
| `password = "..."` | quoted assignment, ≥ 8 chars between the quotes |
| `secret = "..."`   | same |
| `api_key = "..."`  | same |

It does not pretend to be exhaustive. It catches the formats people actually leak.

## Before

Claude wants to write:

```python
# in src/config.py
API_KEY = "sk-abcdef0123456789abcdef0123456789abcdef0123456789"
```

The Write tool fires. Without the hook, that line ships to disk and (probably) to git.

## After

The Write is intercepted. Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked: potential hardcoded secret detected (matched pattern: OpenAI API key). Move credentials to environment variables or a secrets manager. Set CLAUDE_ALLOW_SECRETS=1 to override for test fixtures."
  }
}
```

Claude sees the deny + reason and can rewrite the line as `os.environ["OPENAI_API_KEY"]`.

## Install

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/security/block-secrets.sh"
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
fake_key="sk-$(printf 'a%.0s' {1..48})"
echo '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/x.py","content":"API_KEY = \"'"$fake_key"'\""}}' \
  | bash hooks/security/block-secrets.sh; echo "exit: $?"
```

Expected: exit `0`, stdout JSON with `permissionDecision: deny`, reason mentioning `OpenAI API key`.

The repo's bats suite covers this hook in [`tests/security/block-secrets.bats`](../../tests/security/block-secrets.bats).

## Bypass

Set `CLAUDE_ALLOW_SECRETS=1` for the session. Useful for test fixtures with deliberately fake-but-realistic-looking keys. Unset it the moment you're done.

## Safety notes

- No network calls.
- Reads stdin only; does not write to disk.
- Does not log the matched secret. Only the pattern label is in the deny reason — the actual key never leaves stdin.
- Heuristic, not exhaustive. It does not detect base64-encoded secrets, multi-line PEM blocks, or short custom-format tokens. Pair with a pre-commit secret scanner like [gitleaks](https://github.com/gitleaks/gitleaks) for full coverage.
