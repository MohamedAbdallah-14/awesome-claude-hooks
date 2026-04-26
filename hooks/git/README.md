# git hooks

Six hooks that keep Claude Code from making destructive or non-standard git
operations. They cover branch protection, commit message conventions, working
tree safety, conflict detection, and PR context generation.

## What they do

| Hook | Event | Matcher | Blocks? | Description |
|---|---|---|---|---|
| `protect-main-branch` | PreToolUse | Bash | Yes | Blocks force-push, `reset --hard`, `branch -D`, and `checkout -B` targeting protected branches |
| `validate-commit-message` | PreToolUse | Bash | Yes | Enforces Conventional Commits format on `git commit -m` |
| `auto-create-branch` | Stop | — | No (context) | Warns when the session ends with uncommitted work or commits on a protected branch; suggests a branch name |
| `stash-guard` | PreToolUse | Bash | Opt-in | Warns before branch switches, pulls, merges, and `reset --hard` when the working tree is dirty; upgrades to block with `CLAUDE_STASH_GUARD_BLOCK=1` |
| `conflict-detector` | PreToolUse | Edit\|Write\|MultiEdit | Opt-in | Warns before editing a file that contains merge conflict markers; upgrades to block with `CLAUDE_BLOCK_CONFLICT_EDITS=1` |
| `pr-description-gen` | PostToolUse | Bash | No (context) | After `gh pr create` or a push that creates a PR, injects commit log and diff stat as context for writing the PR description |

## Quick-start: safe defaults for any project

Add this to `.claude/settings.json` in your repo (adjust paths):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/git/protect-main-branch.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/git/validate-commit-message.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/git/stash-guard.sh"
          }
        ]
      },
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/git/conflict-detector.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/git/pr-description-gen.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/git/auto-create-branch.sh"
          }
        ]
      }
    ]
  }
}
```

## Per-hook reference

### protect-main-branch

Blocks four categories of destructive operation on protected branches:

- `git push --force` / `git push -f` / `git push --force-with-lease`
- `git reset --hard` (when current branch is protected)
- `git branch -D <protected-branch>`
- `git checkout -B <protected-branch>` (force-recreate)

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_PROTECTED_BRANCHES` | `"main master develop"` | Space-separated list of protected branch names |
| `CLAUDE_ALLOW_FORCE_PUSH` | `0` | Set to `1` to disable all protection |

---

### validate-commit-message

Validates `git commit -m "..."` against Conventional Commits:

```
type(scope): description
```

Valid types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`,
`perf`, `ci`, `build`, `revert`.

Skips validation for `--no-edit`, `--reuse-message` / `-C` (no message
change), and commits without a `-m` flag (editor-based commits).

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_COMMIT_REGEX` | Conventional Commits ERE | Override with a custom POSIX ERE pattern |
| `CLAUDE_SKIP_COMMIT_VALIDATION` | `0` | Set to `1` to bypass |

---

### auto-create-branch

Stop hook. After each session, checks whether the current branch is protected
AND has either uncommitted changes or commits ahead of upstream. If so, outputs
a context block suggesting a feature branch name derived from the most recent
commit message (slugified).

Does not block anything. Output is informational context.

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_AUTO_BRANCH_SUGGEST` | `1` | Set to `0` to disable |
| `CLAUDE_PROTECTED_BRANCHES` | `"main master develop"` | Same as protect-main-branch |

---

### stash-guard

Fires before commands that can silently discard or conflict with uncommitted
changes:

- `git checkout <branch>` / `git switch <branch>`
- `git stash pop` / `git stash apply`
- `git pull` / `git pull --rebase`
- `git reset --hard`
- `git merge <branch>`

If the working tree is dirty, outputs a warning with the current `git status`
and a recommended stash workflow. By default this is a warn-only hook (exits 0
with context). Upgrade to a hard block with `CLAUDE_STASH_GUARD_BLOCK=1`.

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_STASH_GUARD_BLOCK` | `0` | Set to `1` to block instead of warn |
| `CLAUDE_STASH_GUARD_SKIP` | `0` | Set to `1` to disable entirely |

---

### conflict-detector

Before any Edit, Write, or MultiEdit, checks the target file for unresolved
merge conflict markers (`<<<<<<<`, `=======`, `>>>>>>>`). Also detects diff3
base sections (`|||||||`).

Reports marker counts and the line number of the first conflict. By default
this is warn-only. Set `CLAUDE_BLOCK_CONFLICT_EDITS=1` to block.

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_BLOCK_CONFLICT_EDITS` | `0` | Set to `1` to block edits to conflicted files |
| `CLAUDE_CONFLICT_SKIP` | `0` | Set to `1` to disable entirely |

---

### pr-description-gen

PostToolUse hook. Fires after `gh pr create` or any push command whose stdout
or stderr contains a GitHub PR URL. Collects:

- `git log <base>..HEAD --oneline` — every commit in the PR
- `git diff <base>...HEAD --stat` — files and lines changed
- `gh pr view` metadata (title, changed files, additions/deletions) if `gh`
  is available

Injects this as context so Claude has full detail when writing or improving
the PR description. Does not write to any file; does not post anything.

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_PR_AUTO_DESCRIBE` | `1` | Set to `0` to disable |
| `CLAUDE_PR_BASE_BRANCH` | auto-detected | Override the base branch for log/diff |

---

## Notes

- All hooks require `jq`. Install with `brew install jq` or your system
  package manager. Missing `jq` is a soft failure — the hook exits 0 and
  prints a warning to stderr.
- `git` must be on `PATH` for hooks that run git commands. Non-git directories
  are handled gracefully (the hooks exit 0).
- Hooks that interact with `gh` (the GitHub CLI) skip those steps gracefully
  if `gh` is not installed or not authenticated.
- The `protect-main-branch` and `stash-guard` hooks both read
  `CLAUDE_PROTECTED_BRANCHES` so you only need to set it once in your
  environment or shell profile.
