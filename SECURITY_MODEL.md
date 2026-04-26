# Security model

These hooks run with your full user permissions, the same as any shell command Claude Code launches. They are guardrails, not a sandbox.

This document describes what the hooks can and can't protect against, the risk level of each kind of hook, and how to review what you install.

For how to report a vulnerability, see [`SECURITY.md`](SECURITY.md).

## Threats this repo protects against

The blocking and audit hooks were written to reduce these failure modes:

- Accidental secret writes — hardcoded API keys, AWS access key IDs, GitHub PATs, Slack tokens, naive `password = "..."` assignments.
- Catastrophic shell commands — `rm -rf /`, fork bombs, `dd if=/dev/zero of=/dev/sd*`, `mkfs.*`, `curl | bash`.
- Writes to OS system paths — `/etc`, `/usr`, `/sbin`, `/boot`, `/proc`, `/sys`, `/lib`.
- Destructive infrastructure commands — `terraform destroy`, `kubectl delete` without namespace scoping, `aws` calls against production profiles, `docker rm/stop/kill/volume rm` against prod-named resources.
- Irreversible DB operations — `DROP TABLE`, `DROP DATABASE`, `TRUNCATE`, unsafe `DELETE FROM`, migration rollbacks.
- Malformed config files — invalid JSON or YAML stopped before they hit disk.
- Runaway tool loops — rate-limit hook caps tool calls per minute.
- `.env` overwrites — protect-dotenv refuses writes to `.env`, `.env.local`, `.env.production`, etc. (and allowlists `.env.example`).

Every blocking hook ships with a `CLAUDE_*` bypass env var so you can override locally without editing the script.

## Threats this repo does not protect against

- Malicious local users with shell access to your machine. The hooks run as you.
- A compromised shell environment. If `PATH` or `~/.bashrc` is hostile, the hooks are running on top of that.
- Intentionally bypassed env vars. Every block has a documented escape hatch — that's a feature for legitimate use, but means the protection is honor-system if you set `CLAUDE_ALLOW_*=1` carelessly.
- Secrets already present in the repo or in git history. Detection is at write time, not retroactive.
- Vulnerabilities in third-party tools the hooks invoke (`jq`, `python3`, `notify-send`). File those upstream.
- Anything outside Claude Code's control surface. These are Claude Code hooks; they don't see commands run elsewhere on your system.

## Hook risk levels

Each hook in [`hooks.registry.yaml`](hooks.registry.yaml) carries a `risk_level`. Higher levels need more scrutiny before you install them.

| Level | What it does | Examples |
|-------|--------------|----------|
| `passive` | Reads stdin, takes no action other than exiting. | `audit-bash-commands` (logs only) |
| `contextual` | Emits `additionalContext` JSON to inject info into Claude's session. No side effects on your system. | `inject-git-context`, `session-start-context` |
| `modifying` | Writes to local files (logs, formatted code, commit messages, audit trails). Does not touch network. | `auto-format-on-save`, `audit-file-writes`, `auto-changelog` |
| `blocking` | Returns a `permissionDecision: deny` JSON to stop a tool call. Side-effect-free on your system, but stops Claude. | `block-secrets`, `block-dangerous-bash`, `protect-dotenv` |
| `networked` | Calls an external service. Slack/Telegram/Discord webhooks, Anthropic API, Pushover, etc. Subject to rate limits and outage. | `slack-notify`, `ai-code-review`, `pushover-notify` |
| `privileged` | Invokes infrastructure tooling (`kubectl`, `aws`, `terraform`, `docker`, `helm`, `gcloud`). Read-only for these guards, but the binaries themselves are powerful. | `kubernetes-prod-guard`, `aws-prod-guard`, `terraform-destroy-guard` |

The compatibility matrix at [`docs/compatibility.md`](docs/compatibility.md) lists every hook with its risk level, network access, write behavior, and platform support.

## Review guidance

Before installing any hook from this repo (or any other), do these:

1. **Read the script.** Every hook fits on one screen. The header declares its event, dependencies, and `CLAUDE_*` bypass. The body is a few dozen lines of bash. If you can't read it in a minute, don't install it.
2. **Check the `network_access` flag** in the registry. If `true`, look at where the hook posts to. Use a webhook URL you control.
3. **Pin to a specific commit or release tag** in your `settings.json` rather than tracking `main`. Review diffs before bumping.
4. **Run from a clone you control**, not directly from `curl | bash`.
5. **Use `--dry-run`** first when running `scripts/install.sh`. The dry-run prints the exact `settings.json` snippet it would write.
6. **Keep the bypass env vars documented in your team's runbook.** If you set `CLAUDE_ALLOW_DESTROY=1` for a one-time terraform run, unset it after.

Hooks that can block (`security/`, `quality/`, `git/`) ship with bats tests under `tests/<category>/`. Run `make test` to verify they behave as documented.

## How a blocking hook actually blocks

Per the [official Claude Code hooks reference](https://code.claude.com/docs/en/hooks), blocking happens via JSON on stdout with `exit 0`:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "<your reason>"
  }
}
```

Every blocking hook in this repo emits exactly this shape. Claude Code surfaces `permissionDecisionReason` to the model so it can adjust. If a hook in this repo ever exits 2 with stdout JSON, that's a bug — the JSON is dropped on exit 2 and the reason never reaches Claude. File an issue.
