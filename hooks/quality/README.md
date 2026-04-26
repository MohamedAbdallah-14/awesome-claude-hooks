# Quality Gate Hooks

These hooks shift quality enforcement left — catching lint errors, type
regressions, and formatting drift the moment Claude writes a file, rather than
at CI time. Most are **PostToolUse** so they report issues without blocking
Claude's flow; Claude reads the output and can self-correct immediately.

The one PreToolUse hook (`validate-json-yaml`) blocks writes of syntactically
invalid JSON/YAML before a broken config file ever hits disk.

---

## Hooks at a glance

| Hook | Event | Language(s) | What it does | Auto-fix? |
|---|---|---|---|---|
| `eslint-gate.sh` | PostToolUse | JS, JSX, TS, TSX | Runs ESLint after write, reports errors and warnings | No (suggests `--fix`) |
| `prettier-gate.sh` | PostToolUse | JS, JSX, TS, TSX, CSS, JSON, MD | Checks Prettier formatting, shows diff | Yes (`CLAUDE_PRETTIER_AUTO_FIX=1`) |
| `python-lint.sh` | PostToolUse | Python | Runs ruff / flake8 / black (best available) | No (ruff suggests `--fix`) |
| `dart-analyze.sh` | PostToolUse | Dart / Flutter | Runs `dart analyze` or `flutter analyze`, separates errors from warnings | No |
| `tsc-check.sh` | PostToolUse | TS, TSX | Runs `tsc --noEmit`, tracks error count across edits, flags regressions | No |
| `validate-json-yaml.sh` | PreToolUse | JSON, YAML | Validates syntax before write — **blocks** invalid files | Blocks + explains |
| `go-vet.sh` | PostToolUse | Go | Runs `go vet ./...` and `gofmt -l`, optionally runs tests | No (suggests `gofmt -w`) |
| `test-coverage-check.sh` | PostToolUse | TS, JS, Python, Go, Dart | Runs the test file after save, reports pass/fail | No |

---

## Installation

### 1. Choose hooks

Copy the scripts you want into a location of your choice, e.g.:

```
~/.claude/hooks/quality/
```

Make them executable:

```bash
chmod +x ~/.claude/hooks/quality/*.sh
```

### 2. Register in settings.json

Add the hooks to `~/.claude/settings.json` (global) or
`.claude/settings.json` (per project). Mix and match — you don't need all of
them.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/quality/validate-json-yaml.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/quality/eslint-gate.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/quality/prettier-gate.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/quality/python-lint.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/quality/dart-analyze.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/quality/tsc-check.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/quality/go-vet.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/quality/test-coverage-check.sh"
          }
        ]
      }
    ]
  }
}
```

All hooks ignore files that don't match their extension, so registering all of
them under a single broad matcher is safe.

---

## Configuration

Each hook is controlled by environment variables. Set them in your shell
profile or in the `env` block of your settings.json.

| Variable | Hook | Default | Effect |
|---|---|---|---|
| `CLAUDE_ESLINT_CONFIG` | eslint-gate | (auto-discover) | Path to ESLint config |
| `CLAUDE_ESLINT_MAX_WARNINGS` | eslint-gate | `0` | Warnings allowed before reporting |
| `CLAUDE_PRETTIER_AUTO_FIX` | prettier-gate | `0` | Run `prettier --write` automatically |
| `CLAUDE_PYTHON_LINTER` | python-lint | (auto-detect) | Force `ruff`, `flake8`, or `black` |
| `CLAUDE_DART_USE_FLUTTER` | dart-analyze | `0` | Force `flutter analyze` |
| `CLAUDE_TSC_ARGS` | tsc-check | `""` | Extra args passed to `tsc` |
| `CLAUDE_GO_TEST_ON_CHANGE` | go-vet | `0` | Also run `go test ./...` on edits |
| `CLAUDE_RUN_TESTS_ON_SAVE` | test-coverage-check | `0` | Enable test runner (off by default) |
| `CLAUDE_TEST_TIMEOUT` | test-coverage-check | `30` | Timeout in seconds for test runs |

---

## Design notes

**PostToolUse for most hooks.** Linters run after the file is saved so they
operate on the real content. Claude sees the output in the same turn and can
issue a follow-up edit without a round-trip prompt.

**PreToolUse only for validate-json-yaml.** Syntax errors in JSON/YAML are
hard to recover from once written — a malformed `package.json` can break the
whole dev environment. Blocking before write is the right call here.

**Graceful degradation.** Every hook checks for its required tool before
running and emits a warning then exits 0 if the tool is missing. Hooks never
fail silently or cause false blocks due to a missing dependency.

**tsc-check regression tracking.** The TypeScript check caches the previous
error count in `/tmp/claude-tsc-{hash}.prev`. This lets you see at a glance
whether a particular edit made things better, worse, or unchanged — useful in
large codebases where zero errors is not yet the baseline.

**test-coverage-check is opt-in.** Test suites can take anywhere from 2 seconds
to several minutes. The hook is a no-op unless `CLAUDE_RUN_TESTS_ON_SAVE=1` is
set, so it won't slow down every file write by default.
