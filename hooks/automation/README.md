# Automation hooks

Hooks that remove the manual cleanup steps after Claude writes code: format on save, run the matching test file, append to the changelog, commit the result, push to the upstream remote, and keep README versions in sync with the manifest. Anything that mutates git history or pushes is opt-in via an environment variable; formatters are on by default.

## Hooks

- [`auto-format-on-save`](auto-format-on-save.sh) ([catalog](../../docs/hooks.md#automation)) — Runs the language-appropriate formatter (prettier, black, gofmt, dart format, rustfmt, shfmt) after every write. Skips silently if the formatter is missing.
- [`auto-prettier`](auto-prettier.sh) ([catalog](../../docs/hooks.md#automation)) — Runs `prettier --write` on JS/TS/CSS/JSON/MD/YAML files after each write.
- [`auto-run-tests`](auto-run-tests.sh) ([catalog](../../docs/hooks.md#automation)) — Finds the matching test file by convention (Jest, pytest, go test, dart test) and runs it. Opt-in via `CLAUDE_AUTO_TEST_ENABLED=1`.
- [`auto-changelog`](auto-changelog.sh) ([catalog](../../docs/hooks.md#automation)) — At session end, appends a dated entry to `CHANGELOG.md` summarising the user's request. Opt-in via `CLAUDE_AUTO_CHANGELOG=1`.
- [`auto-git-commit`](auto-git-commit.sh) ([catalog](../../docs/hooks.md#automation)) — At session end, stages tracked changes and commits with a `claude:`-prefixed message. Opt-in via `CLAUDE_AUTO_COMMIT=1`. Refuses to commit on `main`/`master`.
- [`auto-push`](auto-push.sh) ([catalog](../../docs/hooks.md#automation)) — Pushes the current branch only if the last commit was made by `auto-git-commit`. Opt-in via `CLAUDE_AUTO_PUSH=1`. Never force-pushes.
- [`auto-update-readme`](auto-update-readme.sh) ([catalog](../../docs/hooks.md#automation)) — When a manifest changes (`package.json`, `pubspec.yaml`, `pyproject.toml`, `Cargo.toml`), updates the version badge and `version:` lines in `README.md`.

## Install just this category

```bash
bash scripts/install.sh --category=automation --global
```

No profile maps directly to this category. Test on a throwaway branch first if you plan to enable the commit and push hooks. The formatters and `auto-run-tests` are safe to enable on any repo.
