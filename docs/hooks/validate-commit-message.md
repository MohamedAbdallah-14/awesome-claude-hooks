# `validate-commit-message`

> Source: [`hooks/git/validate-commit-message.sh`](../../hooks/git/validate-commit-message.sh)
> Event: `PreToolUse` (matcher `Bash`)
> Risk level: `blocking`
> Bypass: `CLAUDE_SKIP_COMMIT_VALIDATION=1`

## Problem

Claude commits with `git commit -m "updates"`. A week later you're trying to figure out which commit broke the deploy and the entire log reads "fix", "wip", "updates", "more changes". Conventional Commits exists because that history is grep-friendly, changelog-friendly, and tells reviewers what changed without reading the diff. The fix is to enforce the format at commit time, not at review time.

This hook validates `-m "..."` commit messages against the Conventional Commits regex and blocks anything that doesn't match.

## What it catches

| Message | Result |
|---------|--------|
| `feat(auth): add OAuth2 login flow` | Allowed |
| `fix: correct null pointer in payment handler` | Allowed |
| `chore(deps): bump lodash to 4.17.21` | Allowed |
| `feat!: drop Node 14 support` | Allowed (`!` for breaking change) |
| `updates` | **Blocked.** No type prefix. |
| `wip stuff` | **Blocked.** |
| `Fixed a bug` | **Blocked.** Wrong case, no colon. |

Skipped automatically for:

- `git commit --amend --no-edit` (keeps existing message)
- `git commit --no-edit`
- `git commit -C <ref>` / `--reuse-message`
- Editor-driven commits (no `-m` flag) — can't validate before the editor runs

Default regex:

```
^(feat|fix|docs|style|refactor|test|chore|perf|ci|build|revert)(\([a-zA-Z0-9_/.-]+\))?(!)?: .{1,}
```

Override via `CLAUDE_COMMIT_REGEX` if your team uses a different convention.

## Before

Claude wants to run:

```
git commit -m "fixed the thing"
```

Without the hook, "fixed the thing" lands in `git log` forever.

## After

The Bash call is intercepted. Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Commit message does not follow Conventional Commits format.\n\nMessage: \"fixed the thing\"\n\nRequired format: type(scope): description\n  - type must be one of: feat, fix, docs, style, refactor, test, chore, perf, ci, build, revert\n  - scope is optional (parentheses)\n  - description must follow the colon and a space\n\nExamples of valid messages:\n  feat(auth): add OAuth2 login flow\n  fix: correct null pointer in payment handler\n  chore(deps): bump lodash to 4.17.21\n  docs: update README with setup instructions\n\nSet CLAUDE_SKIP_COMMIT_VALIDATION=1 to bypass, or set CLAUDE_COMMIT_REGEX to use a custom pattern."
  }
}
```

Claude rewrites it as `fix: handle null payment handler input`.

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
            "command": "/abs/path/to/hooks/git/validate-commit-message.sh"
          }
        ]
      }
    ]
  }
}
```

Or as part of the `git` profile:

```bash
bash scripts/install.sh --profile=git --global
```

## Test locally

```bash
# Blocked
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m \"updates\""}}' \
  | bash hooks/git/validate-commit-message.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

```bash
# Allowed
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m \"feat(api): add /healthz endpoint\""}}' \
  | bash hooks/git/validate-commit-message.sh; echo "exit: $?"
```

Expected: exit `0`, no JSON output.

```bash
# Bypass
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git commit -m \"updates\""}}' \
  | CLAUDE_SKIP_COMMIT_VALIDATION=1 bash hooks/git/validate-commit-message.sh; echo "exit: $?"
```

Expected: exit `0`, no JSON output.

The repo's bats suite covers this hook in [`tests/git/validate-commit-message.bats`](../../tests/git/validate-commit-message.bats).

## Bypass

`CLAUDE_SKIP_COMMIT_VALIDATION=1` disables validation entirely for the session. Use it for legacy repos that haven't migrated to Conventional Commits yet, or while you're rewriting history with a custom format.

For one-off custom formats, prefer overriding `CLAUDE_COMMIT_REGEX` to the team's pattern instead of disabling the hook. Example: `CLAUDE_COMMIT_REGEX='^\[[A-Z]+-[0-9]+\] '` for a Jira-prefixed convention.

## Safety notes

- No network calls.
- Reads stdin only; never invokes git.
- The message extractor handles `-m "msg"` and `-m 'msg'`. Multi-line `-m "$(cat <<EOF ... EOF)"` here-doc forms are passed through as-is and validated against the first line, which is the conventional rule anyway.
- Editor-driven commits (`git commit` with no `-m`) are not validated — the hook fires before the editor opens. Pair with a `commit-msg` git hook for that case.
- The regex is permissive on description content. It does not enforce length, capitalization, or imperative mood. Add those as extra rules via `CLAUDE_COMMIT_REGEX` if needed.
