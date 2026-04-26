# `protect-dotenv`

> Source: [`hooks/security/protect-dotenv.sh`](../../hooks/security/protect-dotenv.sh)
> Event: `PreToolUse` (matcher `Write|Edit|MultiEdit`)
> Risk level: `blocking`
> Bypass: `CLAUDE_ALLOW_ENV_WRITES=1`

## Problem

`.env` files contain real secrets and Claude has no way to know that. A "tidy up the environment loading" change can rewrite `.env.production` with a stripped-down version, dropping every key the app needed at startup. Recovery is a Slack thread asking the team to repaste the keys nobody remembers anymore.

This hook refuses any Claude write to a `.env*` file (with a documented allowlist for example/template variants) and tells the model to use environment variables or a secrets manager instead.

## What it catches

Filename patterns blocked:

- `.env`
- `.env.local`
- `.env.production`
- `.env.development`
- `.env.test`
- `.env.staging`
- Any path ending in `*.env` (e.g. `config/database.env`)

Allowed (these aren't secret stores):

- `.env.example`
- `.env.sample`
- `.env.template`
- `.env.dist`

## Before

Claude wants to write:

```
.env.production:
DATABASE_URL=postgres://localhost/dev_temp
```

Without the hook, the production env file gets clobbered.

## After

The Write is intercepted. Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Blocked: write to env file '/path/.env.production' is not allowed. Env files typically contain secrets and should be managed manually. Set CLAUDE_ALLOW_ENV_WRITES=1 to override."
  }
}
```

Claude pivots to writing to `.env.example` (allowed) or to documenting the change in the README without touching the live env file.

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
            "command": "/abs/path/to/hooks/security/protect-dotenv.sh"
          }
        ]
      }
    ]
  }
}
```

## Test locally

```bash
echo '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/.env","content":"FOO=bar"}}' \
  | bash hooks/security/protect-dotenv.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

Test that `.env.example` is allowed:

```bash
echo '{"hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/.env.example","content":"FOO=placeholder"}}' \
  | bash hooks/security/protect-dotenv.sh; echo "exit: $?"
```

Expected: exit `0`, no JSON output (allowed).

Coverage: [`tests/security/protect-dotenv.bats`](../../tests/security/protect-dotenv.bats).

## Bypass

`CLAUDE_ALLOW_ENV_WRITES=1` for the session. The intended use case is project scaffolding — when you're deliberately generating a fresh `.env` from a template script. Unset it after.

## Safety notes

- No network calls. No state.
- Matches by basename, not full path — so `path/to/.env` and `.env` are both caught, and `.env.example` in any directory is allowed.
- This hook does not look inside the file. It only refuses the write. If you need to scan content for secrets too, run it alongside [`block-secrets`](block-secrets.md).
