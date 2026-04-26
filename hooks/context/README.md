# Context Injection Hooks

These hooks feed Claude Code information it wouldn't otherwise have — the current git state, TypeScript errors, running containers, package manifests — so its responses reflect the real state of your project rather than what it last observed.

## Why context injection matters

Claude Code is stateless between tool calls. It doesn't automatically know that you pushed a new commit, that `tsc` now has 14 errors, or that the container it's about to `exec` into isn't running. Context injection hooks close that gap by running shell commands at the right moment and surfacing the results inside Claude's active context.

Two injection patterns are used here:

**Stop hooks** write a markdown file to `~/.claude/context/`. Claude reads that directory automatically at the start of each turn (when configured to do so via `context_paths`). Use this for ambient state — git status, environment versions, test results — that should always be available, not just before specific tool calls.

**PreToolUse hooks** output a JSON response with a `"context"` field. Claude Code surfaces that text as context immediately before the tool executes. Use this for targeted, on-demand information tied to a specific action (e.g., "show me this file's git log before I edit it").

## Hooks

| Name | Event | Matcher | Description | Injects |
|------|-------|---------|-------------|---------|
| `inject-git-context.sh` | Stop | — | Writes repo state after each response | Branch, `git status`, last 3 commits, merge conflicts |
| `inject-recent-commits.sh` | PreToolUse | `Edit\|Write\|MultiEdit` | File-level git log before editing | Last N commits for the specific file being changed |
| `inject-test-results.sh` | Stop | — | Parses Jest JSON or generic test output | Pass/fail counts, failing test names |
| `inject-typescript-errors.sh` | PreToolUse | `Edit\|Write\|MultiEdit` | Runs `tsc --noEmit` before editing `.ts`/`.tsx` files | Error count + first 20 diagnostics (cached 30s) |
| `inject-env-summary.sh` | Stop | — | Snapshots environment after each response | Tool versions, OS, Docker state, git remote, env var names (no values) |
| `inject-package-info.sh` | PreToolUse | `Edit\|Write\|MultiEdit` | Summarises manifest before editing it | Name, version, top deps for package.json / pubspec.yaml / requirements.txt / go.mod |
| `inject-docker-status.sh` | PreToolUse | `Bash` | Checks containers before any docker command | Running containers table, compose project list |
| `inject-file-history.sh` | PreToolUse | `Read` | Injects git blame summary before reading a file | Last modifier, commit frequency, open TODO/FIXME lines |

## The context directory

Stop hooks in this collection write to `~/.claude/context/`. Files written there:

```
~/.claude/context/
  git-status.md        # written by inject-git-context.sh
  test-results.md      # written by inject-test-results.sh
  env-summary.md       # written by inject-env-summary.sh
```

The directory is created automatically by each hook on first run. You can read any of these files manually, add your own, or reference them in your `CLAUDE.md`.

## Configuration variables

| Variable | Hook | Default | Purpose |
|----------|------|---------|---------|
| `CLAUDE_GIT_CONTEXT_MAX_FILES` | inject-git-context | `50` | Max lines of `git status --short` to capture |
| `CLAUDE_GIT_LOG_COUNT` | inject-recent-commits | `5` | Commits to show per file |
| `CLAUDE_TEST_RESULTS_FILE` | inject-test-results | _(auto-detect)_ | Explicit path to test output file |
| `CLAUDE_TSC_TIMEOUT` | inject-typescript-errors | `10` | Seconds before tsc is killed |
| `CLAUDE_ENV_SUMMARY_INCLUDE_VERSIONS` | inject-env-summary | `1` | Set to `0` to skip tool version checks |

Set these in your shell profile or in the `env` block of your `settings.json`.

## settings.json — enable all context hooks

Add this to `~/.claude/settings.json` (global) or `.claude/settings.json` (per-project):

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/context/inject-git-context.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/context/inject-test-results.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/context/inject-env-summary.sh"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/context/inject-recent-commits.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/context/inject-typescript-errors.sh"
          },
          {
            "type": "command",
            "command": "/path/to/hooks/context/inject-package-info.sh"
          }
        ]
      },
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/context/inject-docker-status.sh"
          }
        ]
      },
      {
        "matcher": "Read",
        "hooks": [
          {
            "type": "command",
            "command": "/path/to/hooks/context/inject-file-history.sh"
          }
        ]
      }
    ]
  }
}
```

Replace `/path/to/hooks/context/` with the absolute path to this directory.

## Making the scripts executable

```bash
chmod +x /path/to/hooks/context/*.sh
```

## Performance notes

- **inject-typescript-errors** caches its output for 30 seconds per project. Running it on 10 files in quick succession only calls `tsc` once.
- **inject-env-summary** and **inject-git-context** run on every Stop event. On large monorepos with many changed files, set `CLAUDE_GIT_CONTEXT_MAX_FILES` lower to keep the output readable.
- **inject-file-history** skips binary files and untracked files automatically, so it's safe to leave enabled on all Read calls without worrying about overhead on node_modules or build artifacts.
- All hooks exit 0 with `{"decision":"approve"}` on any error or missing dependency rather than blocking Claude Code. They are designed to be additive, never disruptive.
