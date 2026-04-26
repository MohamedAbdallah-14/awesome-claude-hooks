# `tsc-check`

> Source: [`hooks/quality/tsc-check.sh`](../../hooks/quality/tsc-check.sh)
> Event: `PostToolUse` (matcher `Write|Edit|MultiEdit`)
> Risk level: `non-blocking` (reports only; does not block Claude)
> Bypass: remove the hook, or unset `CLAUDE_TSC_ARGS`

## Problem

Claude writes a `.ts` file that compiles in isolation but breaks the project's type graph — a renamed export that 12 other files import, a narrowed return type that cascades into a parser, a new generic that picks the wrong inference branch. The file looks fine. The project no longer builds. Without a check, Claude won't notice until the user runs `tsc` themselves and pastes the wall of errors back into the chat.

This hook runs `tsc --noEmit` from the project root after every `.ts`/`.tsx` write, counts errors, and compares against the previous count. If the count went up, Claude sees a `REGRESSION` message on the next turn. If it went down or stayed clean, the hook quietly confirms.

## What it catches

Triggers only on `.ts` and `.tsx` writes. Walks up from the file's directory to find the nearest `tsconfig.json`, then runs `tsc --noEmit` from that directory. The error count is cached at `/tmp/claude-tsc-{md5(project-root)}.prev` between runs.

| State | Output to Claude |
|-------|------------------|
| 0 errors | "compiles clean" confirmation |
| Errors increased | `REGRESSION:` line + before/after counts + first 20 errors |
| Errors decreased | "Improved" line + delta + first 20 errors |
| Errors unchanged | Status line + first 20 errors |
| No `tsconfig.json` found | stderr warning, exit 0 |
| `tsc` not installed | stderr warning, exit 0 |

The cache is what makes this useful. A project sitting on 47 known errors won't drown Claude in irrelevant noise — the hook only flags the ones Claude *added*.

`tsc` resolution order: global `tsc` → `<project-root>/node_modules/.bin/tsc` → `npx tsc`.

## Before

Project sits at 12 known TS errors (legacy code). Claude refactors `src/parser.ts`, accidentally narrows a return type from `string | null` to `string`. Six callers that handle the `null` branch now have new errors. The file looks clean. The project no longer builds.

## After

The PostToolUse hook fires. Claude sees in the conversation:

```
[tsc-check] REGRESSION: TypeScript errors INCREASED by 6 in /repo
[tsc-check]   Before this change: 12 error(s)
[tsc-check]   After this change:  18 error(s)

src/handlers/import.ts(34,5): error TS2322: Type 'string' is not assignable to type 'string | null'.
src/handlers/export.ts(12,9): error TS2322: Type 'string' is not assignable to type 'string | null'.
... (4 more)
```

Claude reads the regression on the next turn and either widens the return type back or updates the six callers.

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
            "command": "/abs/path/to/hooks/quality/tsc-check.sh"
          }
        ]
      }
    ]
  }
}
```

For stricter checking, set `CLAUDE_TSC_ARGS="--strict"` in the environment Claude Code launches with. Args are appended to `tsc --noEmit`.

## Test locally

```bash
mkdir -p /tmp/tsc-test && cd /tmp/tsc-test
npm init -y >/dev/null && npm i -D typescript >/dev/null
npx tsc --init >/dev/null

cat > demo.ts <<'EOF'
const x: string = 42
EOF

echo '{"hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"/tmp/tsc-test/demo.ts"}}' \
  | bash $OLDPWD/hooks/quality/tsc-check.sh
```

Expected: stdout reports 1 error (`Type 'number' is not assignable to type 'string'`). Exit `0`. Run a second time after fixing — output flips to "compiles clean".

## Bypass

No env-var bypass — the hook is non-blocking. To suppress:

- Remove the hook from `settings.json` to disable.
- Unset `CLAUDE_TSC_ARGS` if you set it to `--strict` and want to back off.
- Delete the cache file at `/tmp/claude-tsc-*.prev` to reset the baseline (e.g. after a deliberate large refactor that added expected errors).

## Safety notes

- **No network calls.** `tsc` runs locally.
- **Speed**: `tsc --noEmit` over a medium-sized project (10–50k LOC) takes 2–10s. The hook fires on every `.ts`/`.tsx` write, so a refactor session can add real overhead. Use TypeScript's `--incremental` via `tsconfig.json` to amortize cost across runs.
- **Cache**: stored in `/tmp/claude-tsc-{md5}.prev`. The md5 is computed over the project root path, so different repos don't collide. The cache survives across Claude sessions but is wiped on system restart (since it lives in `/tmp`).
- **First run**: with no prior cache, the hook can't detect a regression — it reports the absolute count and seeds the cache for next time.
- **Concurrent edits**: if two edits race, the cache update is last-write-wins. The "regression" detection is approximate, not transactional.
- **Project-mode only**: the hook requires a `tsconfig.json`. Single `.ts` files outside any project are skipped with a warning.
- Reports issues but does not block. Pair with pre-commit `tsc --noEmit` if you want hard enforcement.
