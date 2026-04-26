# Quality hooks

Hooks that shift quality enforcement left, catching lint errors, type regressions, and formatting drift the moment Claude writes a file rather than at CI time. Most are `PostToolUse` so they report issues without blocking; the JSON/YAML validator is `PreToolUse` and blocks invalid syntax before it hits disk.

Each hook is a no-op when its toolchain isn't installed. None of them auto-fix unless you opt in.

## Hooks

- [`eslint-gate`](eslint-gate.sh) ([catalog](../../docs/hooks.md#quality)) — Runs ESLint after writes to `.js`/`.jsx`/`.ts`/`.tsx` and reports errors and warnings.
- [`prettier-gate`](prettier-gate.sh) ([catalog](../../docs/hooks.md#quality)) — Reports formatting diffs for JS/TS/CSS/JSON/MD. Set `CLAUDE_PRETTIER_AUTO_FIX=1` to apply instead.
- [`tsc-check`](tsc-check.sh) ([catalog](../../docs/hooks.md#quality)) — After `.ts`/`.tsx` writes, runs `tsc --noEmit` and flags regressions vs. the cached previous error count.
- [`python-lint`](python-lint.sh) ([catalog](../../docs/hooks.md#quality)) — Runs the best available Python linter (ruff > flake8 > black --check) on `.py` writes.
- [`go-vet`](go-vet.sh) ([catalog](../../docs/hooks.md#quality)) — Runs `go vet ./...` and `gofmt -l` on `.go` writes. Optionally runs the package's tests.
- [`dart-analyze`](dart-analyze.sh) ([catalog](../../docs/hooks.md#quality)) — Runs `dart analyze` (or `flutter analyze`) on `.dart` writes; separates errors from warnings.
- [`validate-json-yaml`](validate-json-yaml.sh) ([catalog](../../docs/hooks.md#quality)) — Validates `.json`/`.yaml`/`.yml` syntax before write and **blocks** invalid content.
- [`test-coverage-check`](test-coverage-check.sh) ([catalog](../../docs/hooks.md#quality)) — When a test file is written, detects the framework and runs that file. Off by default, opt-in via `CLAUDE_RUN_TESTS_ON_SAVE=1`.

## Install just this category

The `quality` profile installs every hook here:

```bash
bash scripts/install.sh --profile=quality --project
```

Or use the category flag:

```bash
bash scripts/install.sh --category=quality --project
```

Use `--project` so the gates apply to the repo where the lint config lives.
