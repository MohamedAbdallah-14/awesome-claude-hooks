# `auto-format-on-save`

> Source: [`hooks/automation/auto-format-on-save.sh`](../../hooks/automation/auto-format-on-save.sh)
> Event: `PostToolUse` (matcher `Write|Edit|MultiEdit`)
> Risk level: `non-blocking` (modifies files in place)
> Bypass: `CLAUDE_AUTOFORMAT_ENABLED=0` or `CLAUDE_AUTOFORMAT_SKIP_TYPES`

## Problem

Claude writes code with whatever indentation style it last saw. Two files in, the diff is half logic and half tab-vs-spaces churn. Reviews stall on formatting. CI fails on `prettier --check`. The next session reads the messy file and matches the messy style, compounding the drift.

This hook runs the project's own formatter against every file Claude touches, so the version on disk always matches what `prettier`, `black`, `gofmt`, or `rustfmt` would produce. Claude never has to remember the project's style — the formatter enforces it on every write.

## What it does

After every `Write`/`Edit`/`MultiEdit`, detects the file extension and runs the matching formatter against the file in place. If the formatter is missing, logs a warning to stderr and exits 0 — never blocks Claude.

Formatter selection and fallback chain:

| Extension | Primary | Fallbacks |
|-----------|---------|-----------|
| `.js` `.jsx` `.ts` `.tsx` | project-local `prettier` | global `prettier` → `npx prettier` → project-local `eslint --fix` → global `eslint --fix` |
| `.py` | `black --quiet` | `ruff format` → `autopep8 --in-place` |
| `.go` | `gofmt -w` | none |
| `.dart` | `dart format` | none |
| `.rs` | `rustfmt` | none |
| `.sh` `.bash` | `shfmt -w` | none |
| anything else | skipped silently | n/a |

Project-local binaries (`node_modules/.bin/prettier`, `node_modules/.bin/eslint`) are preferred over globally installed versions, so the formatter version matches the project's `package.json`.

Skipped paths (no formatting attempted):

- `*/node_modules/*`
- `*/dist/*`, `*/build/*`, `*/.next/*`
- `*/vendor/*`, `*/target/*`

## Before

Claude writes `src/api/users.ts` with 2-space indents, single quotes, and missing trailing commas. The project's `.prettierrc` says 4 spaces, double quotes, trailing commas everywhere. The next CI run fails on `prettier --check`. The user asks Claude to fix it. Claude reformats by hand, gets it 80% right, and now the diff has formatting changes mixed into the next feature commit.

## After

The PostToolUse hook fires after every write. `prettier --write src/api/users.ts` runs against the file using the project's config. The on-disk version matches the project's style before the next tool call sees it. CI stays green. Diffs stay focused.

stderr from the hook (visible to Claude):

```
[auto-format-on-save] Formatted /repo/src/api/users.ts with prettier
```

## Install

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "/abs/path/to/hooks/automation/auto-format-on-save.sh"
          }
        ]
      }
    ]
  }
}
```

The hook is opt-out (`CLAUDE_AUTOFORMAT_ENABLED=1` is the default). Set it to `0` to disable without removing the hook.

## Test locally

```bash
mkdir -p /tmp/fmt-test && cd /tmp/fmt-test
printf 'const x={a:1,b:2}\n' > demo.js
echo '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/fmt-test/demo.js"}}' \
  | bash $OLDPWD/hooks/automation/auto-format-on-save.sh
cat demo.js
```

Expected: `demo.js` is rewritten with prettier's formatting (assuming prettier is installed). stderr line confirms which formatter ran.

To verify the skip-types env var:

```bash
echo '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/fmt-test/demo.py"}}' \
  | CLAUDE_AUTOFORMAT_SKIP_TYPES=py bash $OLDPWD/hooks/automation/auto-format-on-save.sh
```

Expected: stderr message indicating the file was skipped because of the skip list.

## Bypass

Two switches:

- `CLAUDE_AUTOFORMAT_ENABLED=0` — disables the hook entirely for the session. Use when running formatters locally would be slower than letting Claude finish a batch of edits first.
- `CLAUDE_AUTOFORMAT_SKIP_TYPES=py:rs` — colon-separated list of extensions to skip. Use when one language's formatter is broken or pinned to a wrong version, but the rest should keep running.

The hook also auto-skips vendored paths (`node_modules`, `dist`, `build`, `.next`, `vendor`, `target`) so generated code never gets reformatted.

## Safety notes

- **In-place modification**: the formatter rewrites the file Claude just wrote. If Claude's content was syntactically invalid, prettier/black will likely fail and leave the file as-is — the hook logs a warning and exits 0.
- **No network calls.** Every formatter is local.
- **Git noise**: if you run this on a repo where some files are intentionally non-conformant (e.g. fixtures), add their extensions to `CLAUDE_AUTOFORMAT_SKIP_TYPES` or move them under a vendored path.
- **Race condition**: the hook fires after each individual `Write`. Multi-file edits format file-by-file, not as a batch. For massive refactors, expect N formatter invocations.
- **Formatter version drift**: project-local binaries are preferred, but if a project lacks `node_modules`, the hook falls back to whatever's globally installed. Pin formatter versions in your project for reproducibility.
- The shell formatter `shfmt` is not installed by default on macOS. If you don't write shell scripts via Claude, ignore the warning.
