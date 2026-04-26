# Go Starter Pack

Pre-configured Claude Code hooks and project instructions for Go applications and services.

## What's included

**settings.json hooks**
- Pre-Bash: blocks secrets and `.env` mutations, blocks dangerous shell commands.
- Pre-edit/write: blocks secrets in any file being touched.
- Post-edit on `.go` files: runs `go vet` after every file change to catch common mistakes immediately.
- Post-Bash: injects recent git commits into context, audits bash commands run during the session.
- On stop: desktop notification (Linux primary, macOS fallback), git context summary, session stats.

**CLAUDE.md rules**
- No `_` for error returns — handle every error.
- `context.Context` as first param for all I/O and long-running operations.
- `defer` for all cleanup.
- Interfaces defined at the consumption site, kept small (1-2 methods).
- No global mutable state, no `init()` except for registration patterns.
- Tests with `-race` flag — data races are bugs that block merging.
- Table-driven tests as the default pattern.

## Setup

1. Copy `settings.json` to `.claude/settings.json` in your project root.
2. Copy `CLAUDE.md` to your project root.
3. Hooks in `settings.json` are pre-configured to use `~/.claude/hooks/hooks` — the default clone path from the quick-start. If you cloned the repo elsewhere, do a find-and-replace of `~/.claude/hooks/hooks` with your actual path.
4. Verify `go-vet.sh` and `audit-bash-commands.sh` paths match your hooks directory structure.
