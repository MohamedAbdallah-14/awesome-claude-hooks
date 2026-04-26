# iOS Starter Pack

Drop-in `settings.json` for iOS / macOS Swift projects. Layers `safe-default` with secret/dotenv blocks, JSON/YAML validation (Fastlane, GitHub Actions, `Info.plist`-adjacent configs), and `main`-branch protection.

## Hooks included

**Pre-Bash**
- `security/block-secrets`, `security/protect-dotenv`, `security/block-dangerous-bash`, `security/audit-bash-commands`.
- `git/protect-main-branch`.

**Pre-Edit/Write**
- `security/block-secrets`, `quality/validate-json-yaml`.

**Post-Edit/Write**
- `security/audit-file-writes`.

**Post-Bash**
- `context/inject-recent-commits`.

**SessionStart**
- `session/context-threshold-guard`.

**Stop**
- `notifications/desktop-notify`, `session/session-summary`, `context/inject-git-context`, `cost/log-tool-usage`.

## Missing: Swift-specific gates

There is no dedicated Swift quality hook (no `swiftlint-gate`, no `swift-format-gate`, no `xcodebuild-test-gate`). **Follow-up:** add `quality/swiftlint-gate.sh` (wrap `swiftlint --strict`) and `quality/swift-format-gate.sh`. The pack is security + workflow only on the Swift side until then.

## Install

```bash
cp ~/.claude/awesome-hooks/starter-packs/ios/settings.json .claude/settings.json
cp ~/.claude/awesome-hooks/starter-packs/ios/CLAUDE.md ./CLAUDE.md
```

Closest matching profile:

```bash
bash scripts/install.sh --profile=safe-default --global
```

## Notes

- Paths assume `~/.claude/awesome-hooks`. Find-and-replace if you cloned elsewhere.
- Replace `<YourScheme>` in `CLAUDE.md` with your actual Xcode scheme name before relying on the test command.
