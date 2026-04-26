# Flutter Starter Pack

Drop-in `settings.json` for Flutter / Dart projects. Layers `safe-default` with `dart analyze`, `dart format`, and a post-bash test-coverage check.

## Hooks included

**Pre-Bash**
- `security/block-secrets`, `security/protect-dotenv`, `security/block-dangerous-bash`, `security/audit-bash-commands`.
- `git/conflict-detector` — flags unresolved merge markers.

**Pre-Edit/Write**
- `security/block-secrets`, `quality/validate-json-yaml`.

**Post-Edit/Write**
- `quality/dart-analyze` — runs `dart analyze` on the touched file.
- `automation/auto-format-on-save` — `dart format` on save.
- `security/audit-file-writes` — write log.

**Post-Bash**
- `context/inject-recent-commits`.
- `quality/test-coverage-check` — surfaces coverage gaps after `flutter test` runs.

**SessionStart**
- `session/context-threshold-guard`.

**Stop**
- `notifications/desktop-notify`, `session/session-summary`, `context/inject-git-context`.

## Install

```bash
cp ~/.claude/awesome-hooks/starter-packs/flutter/settings.json .claude/settings.json
cp ~/.claude/awesome-hooks/starter-packs/flutter/CLAUDE.md ./CLAUDE.md
```

Closest matching profile:

```bash
bash scripts/install.sh --profile=quality --global
```

## Notes

- Paths assume `~/.claude/awesome-hooks`. Find-and-replace if you cloned elsewhere.
- `dart-analyze.sh` and `auto-format-on-save.sh` need the Dart SDK on `PATH`.
- Update the state-management note in `CLAUDE.md` to match your actual package (`flutter_bloc` or `flutter_riverpod`).
