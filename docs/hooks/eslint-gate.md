# `eslint-gate`

> Source: [`hooks/quality/eslint-gate.sh`](../../hooks/quality/eslint-gate.sh)
> Event: `PostToolUse` (matcher `Write|Edit|MultiEdit`)
> Risk level: `non-blocking` (reports only; does not block Claude)
> Bypass: remove the hook, or set `CLAUDE_ESLINT_MAX_WARNINGS` very high

## Problem

Claude writes a TS file using `==`, an unused import, and an `any` your team's config disallows. The file lands on disk. Claude doesn't know your ESLint rules and won't notice until you run `npm run lint` later — at which point the violations are buried under three more files of changes that depend on them.

This hook runs ESLint against every JS/TS file Claude writes and feeds the violations back into the conversation immediately. Claude sees the lint output on the next turn and can fix the issues before building anything else on top.

## What it catches

Runs ESLint with `--format compact --max-warnings <N>` against any file with these extensions:

| Extension | Behavior |
|-----------|----------|
| `.js` `.jsx` `.ts` `.tsx` | Linted |
| anything else | Skipped silently |

What gets reported back to Claude (via stdout, visible in the conversation):

| Outcome | Output |
|---------|--------|
| ESLint exits 0 | Single-line "no issues" confirmation |
| ESLint exits non-zero | Full compact-format issue list + a hint to run `eslint --fix` |
| ESLint not installed | Single warning line on stderr, exit 0 |
| `jq` missing | Single warning line on stderr, exit 0 |

The hook does not return a `decision: "block"` payload. Claude sees the lint output as informational text and decides what to do next. In practice this is enough — the parent session reads "ESLint found issues in foo.ts" and patches them on the very next turn.

## Before

Claude writes `src/utils/parse.ts`:

```ts
import fs from 'fs'
import path from 'path'

export function parse(s) {
  if (s == null) return {}
  return JSON.parse(s)
}
```

`path` is unused. `s` has no type. `==` violates `eqeqeq`. The file lands. Claude moves on. CI fails an hour later.

## After

The PostToolUse hook fires. Claude sees in the conversation:

```
[eslint-gate] ESLint found issues in /repo/src/utils/parse.ts:
/repo/src/utils/parse.ts: line 2, col 1, Error - 'path' is defined but never used. (no-unused-vars)
/repo/src/utils/parse.ts: line 4, col 21, Error - Argument 's' should be typed. (@typescript-eslint/explicit-module-boundary-types)
/repo/src/utils/parse.ts: line 5, col 9, Error - Expected '===' and instead saw '=='. (eqeqeq)

3 problems

[eslint-gate] Fix the issues above, or run: eslint --fix /repo/src/utils/parse.ts
```

Claude reads the output on the next turn and patches all three before continuing.

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
            "command": "/abs/path/to/hooks/quality/eslint-gate.sh"
          }
        ]
      }
    ]
  }
}
```

ESLint resolution order: global `eslint` → `<file-dir>/node_modules/.bin/eslint` → `npx eslint`. Project-local config (`.eslintrc*`, `eslint.config.js`) is auto-discovered.

## Test locally

```bash
mkdir -p /tmp/lint-test && cd /tmp/lint-test
npm init -y >/dev/null && npm i -D eslint >/dev/null
npx eslint --init  # pick a minimal config

cat > demo.ts <<'EOF'
const x = 1
if (x == 1) console.log('match')
EOF

echo '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/lint-test/demo.ts"}}' \
  | bash $OLDPWD/hooks/quality/eslint-gate.sh
```

Expected: stdout shows ESLint compact output flagging `==`. Exit `0`.

## Bypass

There's no env-var bypass — the hook is non-blocking, so there's nothing to override. To suppress noise:

- `CLAUDE_ESLINT_MAX_WARNINGS=999` — treat warnings as informational. Errors still report.
- `CLAUDE_ESLINT_CONFIG=/path/to/.eslintrc` — point to a different config (e.g. a relaxed one for prototyping).
- Remove the hook from `settings.json` to disable entirely.

## Safety notes

- **No network calls.** ESLint runs locally against the file on disk.
- **Speed**: linting one file is fast (<1s on most projects). Linting 50 files in a row across a large refactor is not — expect a few seconds of overhead per Claude turn.
- **Config discovery**: ESLint walks up from the file's directory looking for a config. If the file is outside any project (`/tmp/foo.ts`), ESLint may fail with "no config found" — the hook reports the error verbatim.
- **TypeScript projects**: ESLint with `@typescript-eslint` requires a `parserOptions.project` setting. If your config uses it, the file must be included in the referenced `tsconfig.json` or ESLint will error.
- The hook reports issues but does not block. Pair with `tsc-check` for stronger correctness signal, or wire ESLint into pre-commit if you want hard enforcement.
