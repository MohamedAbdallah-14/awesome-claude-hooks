# `aws-prod-guard`

> Source: [`hooks/devops/aws-prod-guard.sh`](../../hooks/devops/aws-prod-guard.sh)
> Event: `PreToolUse` (matcher `Bash`)
> Risk level: `blocking`
> Bypass: `CLAUDE_ALLOW_AWS_PROD=1`

## Problem

`AWS_PROFILE=prod` is set in the shell because somebody ran a one-off describe an hour ago and forgot to switch back. Claude wants to "clean up a stale test bucket" and runs `aws s3 rb s3://customer-data --force`. There is no soft delete on a bucket-removal you weren't supposed to run.

This hook blocks destructive AWS CLI commands when the active profile looks like production. Read-only operations stay allowed so Claude can still inspect prod when it needs to.

## What it catches

Triggers only when the command targets a production-named profile, detected from any of:

- `--profile prod*` flag in the command
- `AWS_PROFILE=prod*` in the environment
- `AWS_DEFAULT_PROFILE=prod*` in the environment

If a prod profile is in play, the hook then checks the operation:

| Operation type | Behavior |
|----------------|----------|
| Read-only verbs (`describe`, `list`, `get`, `ls`, `head`, `lookup`, `scan`, `query`, `search`, `show`, `check`, `test`, `validate`, `preview`, `estimate`, `forecast`, `explain`) | Allowed |
| Destructive verbs (`delete`, `terminate`, `destroy`, `remove`, `deregister`, `detach`, `disassociate`, `disable`, `revoke`, `deprovision`, `drain`, `stop`, `cancel`, `purge`, `wipe`, `retire`, `reset`) | **Blocked** with the matched verb in the reason |
| Anything else (mutating but not on the destructive list, e.g. `aws s3 cp`, `aws ec2 run-instances`) | **Blocked** with a generic prod-profile reason |

Non-AWS commands pass through unconditionally.

## Before

Claude wants to run:

```
aws s3 rb s3://customer-data --force
```

with `AWS_PROFILE=prod-us-east-1`. Without the hook, the bucket and its contents are gone.

## After

The Bash call is intercepted. Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "AWS command targets production profile with destructive operation 'rb'. Set CLAUDE_ALLOW_AWS_PROD=1 to allow."
  }
}
```

For a non-readonly, non-destructive command on a prod profile (e.g. `aws ec2 run-instances`):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "AWS command targets production profile. Set CLAUDE_ALLOW_AWS_PROD=1 to allow."
  }
}
```

Claude switches to a non-prod profile or restages the change for review.

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
            "command": "/abs/path/to/hooks/devops/aws-prod-guard.sh"
          }
        ]
      }
    ]
  }
}
```

Or as part of the `devops` profile:

```bash
bash scripts/install.sh --profile=devops --global
```

## Test locally

```bash
# Blocked destructive on prod profile
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"aws s3 rb s3://x --profile prod-us"}}' \
  | bash hooks/devops/aws-prod-guard.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

```bash
# Allowed read-only on prod profile
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"aws s3 ls --profile prod-us"}}' \
  | bash hooks/devops/aws-prod-guard.sh; echo "exit: $?"
```

Expected: exit `0`, no JSON output.

```bash
# Allowed via opt-in
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"aws s3 rb s3://x --profile prod-us"}}' \
  | CLAUDE_ALLOW_AWS_PROD=1 bash hooks/devops/aws-prod-guard.sh; echo "exit: $?"
```

Expected: exit `0`, no JSON output.

The repo's bats suite covers this hook in [`tests/devops/aws-prod-guard.bats`](../../tests/devops/aws-prod-guard.bats).

## Bypass

`CLAUDE_ALLOW_AWS_PROD=1` for the session. The intended use is "I'm doing an attended prod change and want Claude's hands free for it". Unset it the moment the change is in — leaving it set means the next destructive prod call goes through silently.

A safer pattern: keep the prod profile out of your default shell. Use a dedicated terminal with `AWS_PROFILE=prod-readonly` for inspection and explicitly switch only when running the actual change.

## Safety notes

- No network calls.
- Stateless — reads stdin, inspects environment, makes a decision, exits.
- "Production" is detected by the `prod` prefix on the profile name. Custom naming (`live`, `customer`, `tenant-1`) won't trip it. Rename your prod profiles or extend the hook.
- The destructive-verb list is heuristic. AWS service teams add new mutating verbs constantly. The catch-all "non-readonly on prod profile" rule is what protects against that drift.
- Pair with [`infra-audit-log`](../../hooks/devops/infra-audit-log.sh) (PostToolUse) to keep an audit trail of every aws command Claude runs.
