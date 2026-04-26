# Data Science Starter Pack

Pre-configured Claude Code hooks and project instructions for Python data science and ML projects.

## What's included

**settings.json hooks**
- Pre-Bash: blocks secrets and `.env` mutations, blocks dangerous shell commands, prevents direct pushes to the main branch, guards against accidental database migrations running mid-session.
- Pre-Write: audits file writes for sensitive paths, scans any written SQL for injection patterns.
- Post-Write: runs Python linting (`python-lint.sh`) and an AI security scan on every written file — both matter here because data pipelines often handle credentials and PII.
- On stop: macOS desktop notification, git context summary, session timer, budget alert (useful when running LLM-assisted analysis), and test results injected into context.

**CLAUDE.md rules**
- Virtual environment / conda activation required before any script runs.
- Exact version pinning in `requirements.txt` via `pip freeze`.
- Raw datasets excluded from git (`*.csv`, `*.parquet`, `*.pkl`, and data directories).
- Jupyter notebook outputs cleared before every commit.
- Random seeds set in every experiment script for reproducibility.
- Model checkpoints saved with version + timestamp — never overwrite.
- PII column check before logging any DataFrame.
- All credentials via environment variables, never hardcoded.

## Setup

1. Copy `settings.json` to `.claude/settings.json` in your project root.
2. Copy `CLAUDE.md` to your project root.
3. Hooks use `~/.claude/hooks/hooks` as the base path — the default clone location. If you cloned the hooks repo elsewhere, replace that prefix with your actual path.
4. Add data file patterns from the `CLAUDE.md` Data section to your `.gitignore` if they aren't there already.
