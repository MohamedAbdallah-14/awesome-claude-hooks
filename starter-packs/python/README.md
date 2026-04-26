# Python Starter Pack

Drop-in `settings.json` for Python projects (FastAPI, Django, scripts, libraries). Layers `safe-default` (audit + summary + context guard + desktop notify) with Python-specific quality gates: `ruff` lint, SQL injection scan, dotenv protection, and test-coverage tracking.

## Hooks included

**Pre-Bash**
- `security/block-secrets` — blocks shell commands that would echo or pipe secret-shaped strings.
- `security/protect-dotenv` — refuses writes/exports targeting `.env*`.
- `security/block-dangerous-bash` — kills `rm -rf /`, fork bombs, curl|sh patterns.
- `security/audit-bash-commands` — appends every Bash invocation to `~/.claude/audit/bash.log`.

**Pre-Edit/Write**
- `security/block-secrets` — same matcher, file-write path.
- `security/scan-sql-injection` — flags string-concatenated SQL in any `.py` write.
- `quality/validate-json-yaml` — parses JSON/YAML before they hit disk; broken config never lands.

**Post-Edit/Write**
- `quality/python-lint` — runs `ruff` (or `flake8`/`black --check` if ruff missing) on the touched file.
- `quality/test-coverage-check` — surfaces uncovered lines after edits to source files.
- `security/audit-file-writes` — logs every write target.

**Post-Bash**
- `context/inject-recent-commits` — feeds the last few commits back into context.

**SessionStart**
- `session/context-threshold-guard` — warns when context is approaching the limit.

**Stop**
- `notifications/desktop-notify` — cross-platform desktop banner when Claude finishes.
- `session/session-summary` — appends a one-line summary of the session.
- `context/inject-git-context` — current branch + dirty file list for the next prompt.
- `cost/log-tool-usage` — tool-call counts for the session.

## Install

```bash
# Project-scoped
cp ~/.claude/awesome-hooks/starter-packs/python/settings.json .claude/settings.json
cp ~/.claude/awesome-hooks/starter-packs/python/CLAUDE.md ./CLAUDE.md
```

Or install the closest profile globally and copy this `CLAUDE.md`:

```bash
bash scripts/install.sh --profile=quality --global
```

## Notes

- Paths assume the repo is cloned at `~/.claude/awesome-hooks` (the quick-start clone target). Find-and-replace the prefix if you cloned elsewhere.
- Adjust `CLAUDE.md` framework notes (FastAPI/Django/scripts) and project layout to match reality.
