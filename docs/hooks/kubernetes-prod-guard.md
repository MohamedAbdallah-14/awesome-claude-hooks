# `kubernetes-prod-guard`

> Source: [`hooks/devops/kubernetes-prod-guard.sh`](../../hooks/devops/kubernetes-prod-guard.sh)
> Event: `PreToolUse` (matcher `Bash`)
> Risk level: `blocking`
> Bypass: `CLAUDE_ALLOW_K8S_PROD=1`

## Problem

Claude's current kubeconfig context is `gke_acme_us-central1_prod`. It thinks it's in staging because the conversation has been about staging. It runs `kubectl delete pod -l app=worker` to clean up a stuck job. The pods that drain are real customer traffic, not your dev fixtures.

Production kubectl is the kind of mistake where the second between Enter and the realization is worth more than the rest of the day. This hook intercepts kubectl commands that target production namespaces, contexts, or the live `current-context` when it's named like prod.

## What it catches

| Pattern | Behavior |
|---------|----------|
| `--namespace production` / `-n prod` / `-n production` | **Blocked** |
| `--context <something-prod-something>` (case-insensitive) | **Blocked** |
| Live `kubectl config current-context` matches `prod`/`production`/`prd` | **Blocked** for any kubectl call |
| `kubectl delete ...` with no `--namespace` / `-n` flag | **Blocked** (defaults to current-context's default ns, which could be prod) |
| Other kubectl commands not in a prod context | Allowed |
| Non-kubectl commands | Allowed |

The current-context check shells out to `kubectl config current-context` if `kubectl` is on PATH. If kubectl isn't installed, the live check is skipped — only the in-command flags are evaluated.

## Before

Claude wants to run:

```
kubectl delete pod worker-abc123
```

While `kubectl config current-context` returns `gke_acme_us-central1_prod`. Without the hook, the pod is gone.

## After

The Bash call is intercepted. Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "kubectl command targets production cluster. Set CLAUDE_ALLOW_K8S_PROD=1 to allow."
  }
}
```

Or, for the unscoped-delete case:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "kubectl delete without explicit --namespace flag. Set CLAUDE_ALLOW_K8S_PROD=1 to allow, or add -n <namespace> to scope the command."
  }
}
```

Claude switches context to `staging` or adds `--context staging-cluster -n my-team` first.

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
            "command": "/abs/path/to/hooks/devops/kubernetes-prod-guard.sh"
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
# Blocked: explicit prod namespace
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"kubectl get pods -n production"}}' \
  | bash hooks/devops/kubernetes-prod-guard.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

```bash
# Blocked: prod-named context flag
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"kubectl --context=us-east-prod get pods"}}' \
  | bash hooks/devops/kubernetes-prod-guard.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

```bash
# Allowed via opt-in
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"kubectl get pods -n production"}}' \
  | CLAUDE_ALLOW_K8S_PROD=1 bash hooks/devops/kubernetes-prod-guard.sh; echo "exit: $?"
```

Expected: exit `0`, no JSON output.

The repo's bats suite covers this hook in [`tests/devops/kubernetes-prod-guard.bats`](../../tests/devops/kubernetes-prod-guard.bats).

## Bypass

`CLAUDE_ALLOW_K8S_PROD=1` for the session. Use it for the narrow case of an attended production change where you actually want Claude's help. Unset it the moment the change is in.

For a safer pattern, switch context manually before opening Claude (`kubectl config use-context staging`) and let the live-context check do the work. That way the bypass is unnecessary and the session can't accidentally drift back to prod.

## Safety notes

- No network calls of its own. The live-context check shells out to `kubectl config current-context`, which reads `~/.kube/config` locally.
- Stateless — reads stdin, makes a decision, exits.
- The unscoped-delete rule is conservative: it blocks `kubectl delete` even on non-prod contexts unless you specify a namespace. The fix is to type the namespace, not to disable the hook.
- The context regex is case-insensitive and matches `prod`, `production`, `prd` substrings. Custom prod naming (e.g. `live`, `customer-cluster`) is not detected. Rename your context or extend the hook.
- Pair with [`infra-audit-log`](../../hooks/devops/infra-audit-log.sh) (PostToolUse) to keep an audit trail of every kubectl command Claude runs, including the ones that did pass.
