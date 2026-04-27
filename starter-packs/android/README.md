# Android Starter Pack

Drop-in `settings.json` for Android (Kotlin) projects. Layers `safe-default` with secret/dotenv blocks, JSON/YAML validation, and `main`-branch protection.

## Hooks included

**Pre-Bash**
- `security/block-secrets`, `security/protect-dotenv`, `security/block-dangerous-bash`, `security/audit-bash-commands`.
- `git/protect-main-branch`.

**Pre-Edit/Write**
- `security/block-secrets`, `quality/validate-json-yaml` (covers `*.yml`, `*.json`, GitHub Actions, Fastlane configs).

**Post-Edit/Write**
- `security/audit-file-writes`.

**Post-Bash**
- `context/inject-recent-commits`.

**SessionStart**
- `session/context-threshold-guard`.

**Stop**
- `notifications/desktop-notify`, `session/session-summary`, `context/inject-git-context`, `cost/log-tool-usage`.

## Missing: Kotlin/Android-specific gates

There is no dedicated Kotlin or Gradle quality hook (no `ktlint-gate`, no `detekt-gate`, no `gradle-lint-gate`). **Follow-up:** add `quality/ktlint-gate.sh` (wrap `./gradlew ktlintCheck`) and/or `quality/detekt-gate.sh`. Until then, the pack is security + workflow only on the Kotlin side.

## Install

```bash
cp ~/.claude/awesome-hooks/starter-packs/android/settings.json .claude/settings.json
cp ~/.claude/awesome-hooks/starter-packs/android/CLAUDE.md ./CLAUDE.md
```

Closest matching profile:

```bash
bash scripts/install.sh --profile=safe-default --global
```

## Notes

- Paths assume `~/.claude/awesome-hooks`. Find-and-replace if you cloned elsewhere.
- Add the OWASP Dependency Check Gradle plugin if you want CVE scanning via `./gradlew dependencyCheckAnalyze`.
