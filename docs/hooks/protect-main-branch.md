# `protect-main-branch`

> Source: [`hooks/git/protect-main-branch.sh`](../../hooks/git/protect-main-branch.sh)
> Event: `PreToolUse` (matcher `Bash`)
> Risk level: `blocking`
> Bypass: `CLAUDE_ALLOW_FORCE_PUSH=1`

## Problem

Claude resolves a rebase conflict, ends up on `main`, and reaches for `git reset --hard origin/main` to "clean up" — except your local `main` had three reviewed commits not yet pushed. Or it tries `git push --force` to overwrite the remote after a clean rewrite, taking out a teammate's work that landed five minutes ago. Force-mode git on a shared branch is unrecoverable for everyone except whoever has the right reflog.

This hook blocks the destructive git operations against a configured set of protected branches.

## What it catches

| Command | When it blocks |
|---------|----------------|
| `git push --force` / `-f` / `--force-with-lease` | If a protected branch name appears in the command or as the last token |
| `git reset --hard` | If the current branch is protected |
| `git branch -D <branch>` | If the target is a protected branch |
| `git checkout -B <branch>` | If the target is a protected branch (force-recreate) |

Default protected list: `main master develop`. Override with `CLAUDE_PROTECTED_BRANCHES`.

`--force-with-lease` is treated like `--force`. It's safer in principle but still rewrites shared history; the risk profile is the same for an autonomous tool.

## Before

Claude wants to run:

```
git push --force origin main
```

Or:

```
git reset --hard HEAD~3   # while on main
```

Without the hook, history on the protected branch is gone.

## After

The Bash call is intercepted. Claude receives:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Force-pushing to 'main' is blocked. Protected branches: main master develop. Set CLAUDE_ALLOW_FORCE_PUSH=1 to override."
  }
}
```

Claude switches to a feature branch and opens a PR instead.

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
            "command": "/abs/path/to/hooks/git/protect-main-branch.sh"
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
# Blocked force push
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
  | bash hooks/git/protect-main-branch.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

```bash
# Allowed via opt-in
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}' \
  | CLAUDE_ALLOW_FORCE_PUSH=1 bash hooks/git/protect-main-branch.sh; echo "exit: $?"
```

Expected: exit `0`, no JSON output.

```bash
# Blocked branch deletion
echo '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git branch -D main"}}' \
  | bash hooks/git/protect-main-branch.sh; echo "exit: $?"
```

Expected: exit `0`, JSON `permissionDecision: deny`.

The repo's bats suite covers this hook in [`tests/git/protect-main-branch.bats`](../../tests/git/protect-main-branch.bats).

## Bypass

`CLAUDE_ALLOW_FORCE_PUSH=1` for the session. Intended for the narrow case of "I'm rewriting the history of a feature branch I share with myself". Unset it the moment the operation is done — leaving it set means the next destructive git command goes through silently.

A safer pattern: alias `gpf` to `CLAUDE_ALLOW_FORCE_PUSH=1 git push --force-with-lease`, type the alias yourself when you really mean it.

## Safety notes

- No network calls.
- Reads stdin only; does shell out to `git symbolic-ref --short HEAD` to resolve the current branch for the `reset --hard` check. If you're not in a git repo, the current-branch check is skipped.
- The branch-name match for `git push` is regex-based: it looks for the protected name as the last token or as a `:`-separated refspec. Unusual push syntax (`refs/heads/main:refs/heads/main` chained with comments) may slip through. The defaults catch what Claude actually types.
- Pair with the `git` profile's [`auto-create-branch`](../../hooks/git/auto-create-branch.sh) hook to keep Claude off `main` in the first place.
