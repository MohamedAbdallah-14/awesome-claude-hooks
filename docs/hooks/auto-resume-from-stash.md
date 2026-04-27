# `auto-resume-from-stash`

> Source: [`hooks/git/auto-resume-from-stash.sh`](../../hooks/git/auto-resume-from-stash.sh)
> Event: `SessionStart` (matcher `resume`)
> Risk level: `workflow`
> Bypass: `CLAUDE_AUTO_RESUME_STASH_OFF=1`

## Problem

You're mid-feature. You quit Claude Code (or it crashes). You stashed your in-progress work because committing felt wrong. Next time you `claude --resume`, your work is in `git stash list` somewhere, and you've forgotten which stash belongs to which branch. You re-derive the work or — worse — pop the wrong stash and get a conflict mess.

This hook does the boring half of that workflow automatically.

## What it does

On `SessionStart` with matcher `resume`, the hook:

1. Reads the session's `cwd` and confirms it's a git repo.
2. Finds the current branch (refuses to act on detached HEAD).
3. Walks `git stash list` looking for the first stash whose subject starts with the magic prefix `claude-auto:` AND whose subject names the current branch.
4. If the working tree is clean, pops that stash.
5. Either way, surfaces a one-line `additionalContext` so Claude knows what happened.

If there's no matching stash, the hook does nothing and stays silent.

## The convention

This hook expects you (or a paired SessionEnd hook, or your own habit) to create stashes shaped like:

```bash
git stash push -u -m "claude-auto: $(git rev-parse --abbrev-ref HEAD)"
```

The `claude-auto:` prefix is what tells the hook "this stash is mine to manage." Manually-created stashes — anything without that prefix — are left alone, forever.

You can change the prefix via `CLAUDE_AUTO_STASH_PREFIX` if you don't like the default.

## Why not just `git stash pop`?

Three reasons:

1. **Branch-scoped.** A naive pop would grab the most recent stash regardless of which branch it was made on. This hook only pops stashes whose message names the current branch.
2. **Opt-in via prefix.** It will never touch a stash you made manually. The `claude-auto:` prefix is the contract.
3. **Refuses to clobber.** If the working tree is dirty, the hook refuses to pop and tells you the exact `git stash pop <ref>` command to run yourself once you've cleaned up.

## What Claude sees

On a successful pop:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "auto-resume-from-stash: popped stash@{0} (claude-auto: feature/x) onto branch feature/x. Inspect the working tree before continuing."
  }
}
```

On a dirty-tree skip:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "auto-resume-from-stash: found a matching stash (stash@{0}: claude-auto: feature/x) on branch feature/x but the working tree is dirty. Skipping pop. Resolve or commit current changes, then run: git stash pop stash@{0}"
  }
}
```

On a pop conflict:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "auto-resume-from-stash: attempted to pop stash@{0} but it conflicted. Resolve conflicts manually. git output: <full git output>"
  }
}
```

Claude can react to all three intelligently — keep working, ask you to clean up, or help resolve the conflict.

## Install

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "resume",
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/git/auto-resume-from-stash.sh"
          }
        ]
      }
    ]
  }
}
```

The `matcher: "resume"` is the important bit — you don't want this firing on a fresh `startup`, only when resuming an existing session.

## Config

| Env var | Default | Effect |
|---------|---------|--------|
| `CLAUDE_AUTO_STASH_PREFIX` | `claude-auto:` | Stash subject prefix the hook acts on |
| `CLAUDE_AUTO_RESUME_STASH_OFF=1` | (unset) | Disable the hook entirely |

## Idempotency

A stash, once popped, is gone from `git stash list`, so the next `SessionStart` finds nothing and does nothing. Re-running the hook against a clean tree with no matching stash is always a no-op.

## Safety notes

- Never force-pops. Dirty tree → skip with explicit instructions.
- Never touches stashes without the `claude-auto:` prefix.
- Branch-scoped: a `claude-auto: feature/x` stash is invisible while you're on `main`.
- Detached HEAD → no-op.
- No network calls.
- All git operations are read-only or `stash pop` only — no force, no reset, no checkout.

## Pair with

A simple SessionEnd habit (or hook) to create the matching stash:

```bash
# In a SessionEnd hook, or as a shell alias:
[[ -n "$(git status --porcelain 2>/dev/null)" ]] && \
  git stash push -u -m "claude-auto: $(git rev-parse --abbrev-ref HEAD)"
```

Or run it manually before quitting Claude when you know the work isn't ready to commit.
