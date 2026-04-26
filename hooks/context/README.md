# Context hooks

Hooks that inject just-in-time information into Claude's context so it makes better decisions: who last touched a file, what's currently running in Docker, the project's dependency manifest, the current TypeScript error count, recent test results, and so on. Most are `PreToolUse` to feed Claude before an edit; the rest run on `Stop` to refresh state files Claude reads on its next turn.

These hooks read repo state and, in some cases, write small markdown summaries under `~/.claude/context/`. None of them block tool calls.

## Hooks

- [`inject-git-context`](inject-git-context.sh) ([catalog](../../docs/hooks.md#context)) — On `Stop`, writes branch, status, last 3 commits, and merge-conflict markers to `~/.claude/context/git-status.md`.
- [`inject-recent-commits`](inject-recent-commits.sh) ([catalog](../../docs/hooks.md#context)) — Before edits, injects the file's recent git log so Claude knows what changed and why.
- [`inject-file-history`](inject-file-history.sh) ([catalog](../../docs/hooks.md#context)) — Before reads, injects last committer, 30-day commit count, and any `TODO`/`FIXME` markers.
- [`inject-package-info`](inject-package-info.sh) ([catalog](../../docs/hooks.md#context)) — Before edits to `package.json`, `pubspec.yaml`, `requirements.txt`, or `go.mod`, injects a summary of declared deps.
- [`inject-typescript-errors`](inject-typescript-errors.sh) ([catalog](../../docs/hooks.md#context)) — Before `.ts`/`.tsx` edits, runs `tsc --noEmit` and injects the error count plus first 20 diagnostics. Cached for 30s.
- [`inject-test-results`](inject-test-results.sh) ([catalog](../../docs/hooks.md#context)) — On `Stop`, summarises the most recent jest/pytest/cached test output to `~/.claude/context/test-results.md`.
- [`inject-docker-status`](inject-docker-status.sh) ([catalog](../../docs/hooks.md#context)) — Before any `docker` command, injects the current container state. No-ops if Docker is unreachable.
- [`inject-env-summary`](inject-env-summary.sh) ([catalog](../../docs/hooks.md#context)) — On `Stop`, writes tool versions, OS info, Docker state, and git remote to `~/.claude/context/env-summary.md`. Lists env-var names only, never values.

## Install just this category

```bash
bash scripts/install.sh --category=context --global
```

No profile maps directly to this category. Pair with `--profile=safe-default` to combine context injection with the audit and notification hooks.
