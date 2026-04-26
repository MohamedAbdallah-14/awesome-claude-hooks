# iOS Starter Pack

Pre-configured Claude Code hooks and project instructions for iOS (Swift) apps.

## What's included

**settings.json hooks**
- Pre-Bash: blocks secrets and `.env` mutations, blocks dangerous shell commands, prevents direct pushes to the main branch.
- Pre-Write: audits file writes for sensitive paths, validates any JSON or YAML files before they land.
- Post-Write: runs both an AI code review pass and an AI security scan on every written file — two passes because iOS handles sensitive data (keychain, biometrics, location) where security issues are high-impact.
- On stop: macOS desktop notification, git context summary, session timer.

**CLAUDE.md rules**
- `xcodebuild` / `swift build` enforced — no direct compiler invocations.
- `@Observable` (iOS 17+) preferred over `@ObservedObject` for new code.
- Swift Concurrency (`async/await`, `MainActor`) over `DispatchQueue` for all new async work.
- Retain cycle prevention: `[weak self]` required in closures that could outlive their owner.
- All permissions declared in `Info.plist` before the API call is written.
- No `.p12`, `.mobileprovision`, or API keys in source control.
- All user-facing strings through `NSLocalizedString`.

## Setup

1. Copy `settings.json` to `.claude/settings.json` in your Xcode project root (the folder containing `.xcodeproj` or `Package.swift`).
2. Copy `CLAUDE.md` to the same project root.
3. Hooks use `~/.claude/hooks/hooks` as the base path — the default clone location. If you cloned the hooks repo elsewhere, replace that prefix with your actual path.
4. Replace `<YourScheme>` in the test command inside `CLAUDE.md` with your actual Xcode scheme name.
