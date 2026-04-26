# Python Starter Pack

Pre-configured Claude Code hooks and project instructions for Python projects (FastAPI, Django, or scripts).

## What's included

**settings.json hooks**
- Pre-Bash: blocks secrets, protects `.env` files, blocks dangerous shell commands.
- Pre-edit/write on `.py` files: scans for SQL injection patterns, validates JSON/YAML config files being written.
- Post-edit on `.py` files: runs the Python linter (ruff/flake8) immediately after each file change, audits any file write operations.
- Post-Bash: injects recent git commits for context after shell commands.
- On stop: desktop notification (Linux primary, macOS fallback), git context summary, session stats, tool usage log for cost tracking.

**CLAUDE.md rules**
- Type hints required on all function signatures.
- `pathlib.Path` over `os.path` everywhere.
- No `eval()`/`exec()` with external input, no string-concatenated SQL, no wildcard imports.
- Async code must be fully async — no blocking calls inside `async def`.
- All secrets via `python-dotenv` through a single config module.
- Tests must not touch real databases, network, or filesystem.

## Setup

1. Copy `settings.json` to `.claude/settings.json` in your project root.
2. Copy `CLAUDE.md` to your project root.
3. Replace `$HOOKS_DIR` in `settings.json` with the absolute path to the cloned `awesome-claude-hooks/hooks/` directory.
4. Adjust the framework notes and project layout in `CLAUDE.md` to match your actual structure.
