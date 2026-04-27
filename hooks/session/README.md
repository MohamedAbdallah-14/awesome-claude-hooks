# Session hooks

Hooks tied to session lifecycle events: load project context at the start, name the session after the current branch, inject project-local env vars, back up the transcript before compaction, warn before the context window fills up, and append a daily summary of every session. They run on `SessionStart`, `Stop`, and `PreCompact`.

Three of these hooks (`session-start-context`, `env-file-injector`, `precompact-backup`) run on rare events but matter when they fire; the other three run on every session.

## Hooks

- [`session-start-context`](session-start-context.sh) ([catalog](../../docs/hooks.md#session)) — At session start, injects branch, recent commits, modified files, and any project notes.
- [`session-name-from-branch`](session-name-from-branch.sh) ([catalog](../../docs/hooks.md#session)) — Names the session after the current git branch (slugified) so it shows up labelled in the session list.
- [`env-file-injector`](env-file-injector.sh) ([catalog](../../docs/hooks.md#session)) — Loads `.claude.env` from the repo root and injects key=value pairs as session context. Redacts anything that looks like a real secret.
- [`session-summary`](session-summary.sh) ([catalog](../../docs/hooks.md#session)) — Appends a one-line summary (start time, cwd, tool count) to a daily Markdown log on `Stop`.
- [`context-threshold-guard`](context-threshold-guard.sh) ([catalog](../../docs/hooks.md#session)) — Warns when the transcript size crosses a threshold so you can run `/compact`.
- [`precompact-backup`](precompact-backup.sh) ([catalog](../../docs/hooks.md#session)) — Backs up the full transcript to a timestamped file before compaction so prior turns stay recoverable.

## Install just this category

```bash
bash scripts/install.sh --category=session --global
```

`session-summary` and `context-threshold-guard` are part of the `safe-default` profile:

```bash
bash scripts/install.sh --profile=safe-default --global
```

Use `--global` so the hooks fire across every repo, not just one.
