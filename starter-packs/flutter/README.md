# Flutter Starter Pack

Pre-configured Claude Code hooks and project instructions for Flutter cross-platform apps.

## What's included

**settings.json hooks**
- Pre-edit/Bash: blocks secrets and `.env` mutations, blocks dangerous shell commands, detects merge conflicts before they compound.
- Post-edit on `.dart` files: runs `dart analyze` immediately after each file edit, auto-formats with `dart format`.
- Post-Bash: checks test coverage after test runs, injects recent git commits for context.
- On stop: macOS desktop notification, git context summary, session stats, motivational quote.

**CLAUDE.md rules**
- `const` constructors wherever they compile — enforced as a hard rule, not a suggestion.
- `debugPrint`/logger only, never `print()`.
- Named parameters required for anything with more than 3 args.
- Feature-first folder structure with clear boundaries between features.
- Platform code changes must compile on all target platforms before marking done.

## Setup

1. Copy `settings.json` to `.claude/settings.json` in your Flutter project root.
2. Copy `CLAUDE.md` to your project root.
3. Replace `$HOOKS_DIR` in `settings.json` with the absolute path to the cloned `awesome-claude-hooks/hooks/` directory.
4. Update the state management note in `CLAUDE.md` to match your actual package (`flutter_bloc` or `flutter_riverpod`).
