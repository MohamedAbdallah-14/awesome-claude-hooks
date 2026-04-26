# Data Science Starter Pack

Drop-in `settings.json` for Python data-science / ML projects. Layers `safe-default` with `ruff` lint, SQL injection scan, db-migration guard (for analytical pipelines that talk to warehouses), secret/dotenv blocks, and a budget alert (useful when running LLM-assisted analysis).

## Hooks included

**Pre-Bash**
- `security/block-secrets`, `security/protect-dotenv`, `security/block-dangerous-bash`, `security/audit-bash-commands`.
- `devops/db-migration-guard` — guards against destructive warehouse / Alembic migration commands run mid-session.

**Pre-Edit/Write**
- `security/block-secrets`, `security/scan-sql-injection`, `quality/validate-json-yaml`.

**Post-Edit/Write**
- `quality/python-lint` — runs `ruff` (or `flake8`/`black --check`) on the touched file.
- `security/audit-file-writes`.

**Post-Bash**
- `context/inject-recent-commits`.

**SessionStart**
- `session/context-threshold-guard`.

**Stop**
- `notifications/desktop-notify`, `session/session-summary`, `context/inject-git-context`.
- `cost/budget-alert` — alerts when the session crosses the configured cost threshold.
- `cost/log-tool-usage` — tool-call counts for the session.

## Install

```bash
cp ~/.claude/awesome-hooks/starter-packs/data-science/settings.json .claude/settings.json
cp ~/.claude/awesome-hooks/starter-packs/data-science/CLAUDE.md ./CLAUDE.md
```

Closest matching profile:

```bash
bash scripts/install.sh --profile=quality --global
```

## Notes

- Paths assume `~/.claude/awesome-hooks`. Find-and-replace if you cloned elsewhere.
- Set `BUDGET_ALERT_THRESHOLD` in your environment to tune `cost/budget-alert.sh`.
- Add the `*.csv` / `*.parquet` / `data/` patterns from `CLAUDE.md` to `.gitignore` before committing anything.
- There is no notebook-output-clear hook yet. Add one to your pre-commit or run `jupyter nbconvert --clear-output --inplace` manually.
