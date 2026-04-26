# `terraform-destroy-guard`

> Source: [`hooks/devops/terraform-destroy-guard.sh`](../../hooks/devops/terraform-destroy-guard.sh)
> Event: `PreToolUse` (matcher `Bash`)
> Risk level: `blocking` (with a documented warn-mode for `apply -destroy`)
> Bypass: `CLAUDE_ALLOW_DESTROY=1`

## Problem

`terraform destroy` is the most expensive shell command Claude can type. There is no undo. The state file forgets your prod cluster ever existed and the cloud provider proceeds to delete every resource in it. A confidently-typed `terraform destroy` from a model that just refactored your variables into modules is a real outage shaped exactly like a chat message.

This hook blocks `terraform destroy` (and warns on the lower-risk `terraform apply -destroy`) unless you've explicitly opted into destruction for the session.

## What it catches

| Command | Behavior |
|---------|----------|
| `terraform destroy` (any flags) | **Blocked.** Hard stop. |
| `terraform destroy -auto-approve` | **Blocked.** `-auto-approve` makes it worse, not better. |
| `terraform apply -destroy` | **Warning** to stderr, command allowed. The "soft" form. |
| Anything else `terraform` does | Allowed unconditionally. |

The `apply -destroy` warn-mode exists because that flag is sometimes used legitimately (to remove specific resources from state), and the cost of a false positive there is higher than the cost of a logged warning.

## Before

Claude wants to run:

```
terraform destroy -auto-approve
```

Without the hook, prod is gone in 90 seconds.

## After

The Bash call is intercepted. Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "terraform destroy blocked. Set CLAUDE_ALLOW_DESTROY=1 to allow destructive infra changes."
  }
}
```

The deploy survives.

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
            "command": "/abs/path/to/hooks/devops/terraform-destroy-guard.sh"
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
# Hard block
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"terraform destroy -auto-approve"}}' \
  | bash hooks/devops/terraform-destroy-guard.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

```bash
# Allowed via opt-in
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"terraform destroy"}}' \
  | CLAUDE_ALLOW_DESTROY=1 bash hooks/devops/terraform-destroy-guard.sh; echo "exit: $?"
```

Expected: exit `0`, no JSON output.

```bash
# Soft warn
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"terraform apply -destroy"}}' \
  | bash hooks/devops/terraform-destroy-guard.sh 2>&1
```

Expected: stderr line starting `[terraform-destroy-guard] WARNING:`, action proceeds.

## Bypass

`CLAUDE_ALLOW_DESTROY=1` for the session. The intended use is "I'm about to tear down a sandbox env". Unset it the moment the destroy is done — leaving it set means the next destroy goes through silently, defeating the point.

A safer pattern: alias `tfd` to `CLAUDE_ALLOW_DESTROY=1 terraform destroy` in your shell, type the alias by hand. The point is to make destruction a deliberate, attended act.

## Safety notes

- No network calls.
- Stateless — reads stdin, makes a decision, exits.
- The `apply -destroy` detection is regex-based. It can have false negatives if a future Terraform release renames the flag. The block on the `destroy` subcommand itself is robust.
- Pair with [`infra-audit-log`](../../hooks/devops/infra-audit-log.sh) (PostToolUse) to keep an audit trail of every infra command Claude runs, including the ones that did pass this hook.
