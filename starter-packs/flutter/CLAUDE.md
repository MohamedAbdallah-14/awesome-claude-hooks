# Flutter Project

## Stack

Flutter (cross-platform: iOS, Android, web, desktop). Dart 3+. Check `pubspec.yaml` for the actual Flutter SDK constraint and key dependencies.

## Architecture

Feature-first folder structure. Each feature lives in `lib/features/<feature_name>/` and owns its own UI, state, and domain code. Shared code goes in `lib/core/` (theme, routing, utilities) and `lib/shared/` (reusable widgets).

State management: check `pubspec.yaml` — this project uses either **BLoC** (`flutter_bloc`) or **Riverpod** (`flutter_riverpod`). Don't mix the two.

## Hard rules

**Dart style**
- `const` constructors everywhere they compile. If a widget or object is immutable and all fields are compile-time constants, it must be `const`.
- Prefer `final` over `var`. Use `var` only when the type is obvious from the right-hand side and verbose to write out.
- Use `required` for required named parameters. No nullable required params unless a null value is genuinely valid.
- Avoid `late` except where initialization order genuinely requires it (e.g., `initState`). Document why with a comment.

**Logging**
- Never use `print()`. Use `debugPrint()` for development-only output, or a proper logger package (`logger`, `talker`) for structured logs. Both should be stripped or silenced in release builds.

**Widgets**
- Extract any widget subtree that appears more than once into a named widget class.
- Any function/constructor with more than 3 parameters must use named parameters.
- Prefer `StatelessWidget` + state management over `StatefulWidget` for business logic. Reserve `StatefulWidget` for local UI state (animation controllers, focus nodes, text controllers).

**Platform code**
- Any addition to `android/`, `ios/`, `macos/`, `linux/`, `windows/`, or `web/` must compile on all intended target platforms. Check CI or run `flutter build <platform>` before marking complete.
- Never add platform channel code without a fallback or compile guard for unsupported platforms.

**Never**
- Hardcode colors or text styles inline. Use the theme (`Theme.of(context)`) or defined constants.
- Use `BuildContext` across async gaps without a `mounted` check.
- Import from another feature's internal files. Features communicate through their public API (barrel exports or shared domain models).

## Formatting and analysis

Run before every commit:

```bash
dart format .
dart analyze
flutter test
```

All three must pass clean. `dart analyze` with zero issues is the bar — warnings are not acceptable.

## Tests

- Widget tests: `test/widgets/`
- Unit tests: `test/unit/`
- Integration tests: `integration_test/`
- Use `flutter_test` for widget tests, plain `test` package for unit tests.
- Mock dependencies with `mocktail` or `mockito` — never hit real network in unit or widget tests.

## Adding a feature

1. Create `lib/features/<feature_name>/` with subdirectories: `data/`, `domain/`, `presentation/`.
2. Register routes in the central router (check `lib/core/router/`).
3. Add any new packages to `pubspec.yaml` and run `flutter pub get`.
4. Write at least unit tests for domain logic and a smoke widget test for the main screen.

## Commands

```bash
flutter pub get              # install dependencies
flutter run                  # run on connected device/emulator
flutter test                 # run all tests
flutter build apk            # Android release build
flutter build ios            # iOS release build (macOS required)
dart format .                # format all Dart files
dart analyze                 # static analysis
```
