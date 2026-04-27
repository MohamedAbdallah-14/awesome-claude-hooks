# Git hooks

Hooks that keep Claude from making destructive or non-standard git operations: branch protection, Conventional Commits enforcement, working-tree safety before checkouts and rebases, conflict detection before edits, and PR-context capture when a push or `gh pr create` lands.

## Hooks

- [`protect-main-branch`](protect-main-branch.sh) ([catalog](../../docs/hooks.md#git)) — Blocks `git push --force`, `git reset --hard`, `git branch -D`, and `git checkout -B` against protected branches.
- [`validate-commit-message`](validate-commit-message.sh) ([catalog](../../docs/hooks.md#git)) — Validates `git commit -m` against Conventional Commits. Skips `--amend --no-edit`.
- [`stash-guard`](stash-guard.sh) ([catalog](../../docs/hooks.md#git)) — Warns before checkouts, rebases, merges, or `stash pop`/`apply` while the working tree is dirty. Set `CLAUDE_STASH_GUARD_BLOCK=1` to block instead.
- [`conflict-detector`](conflict-detector.sh) ([catalog](../../docs/hooks.md#git)) — Before edits, checks for unresolved merge-conflict markers and blocks if any are found.
- [`auto-create-branch`](auto-create-branch.sh) ([catalog](../../docs/hooks.md#git)) — On `Stop`, warns when uncommitted changes or new commits exist on a protected branch and suggests a feature-branch name.
- [`pr-description-gen`](pr-description-gen.sh) ([catalog](../../docs/hooks.md#git)) — After `gh pr create` or a push that returns a PR URL, gathers commits, diff-stat, and any existing PR body as context.

## Install just this category

The `team` profile pulls the four most useful hooks here plus a couple from other categories:

```bash
bash scripts/install.sh --profile=team --project
```

Or install everything in this directory:

```bash
bash scripts/install.sh --category=git --project
```

Use `--project` so the rules apply to the repo where they matter, not globally.
