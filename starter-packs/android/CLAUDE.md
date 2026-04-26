# Android Project

## Stack

Android (Kotlin). Check `build.gradle.kts` (or `build.gradle`) for compileSdk, minSdk, and key dependencies.

## Build

- Always use `./gradlew`, never invoke `gradle` directly — the wrapper pins the correct Gradle version.
- Release builds: `./gradlew assembleRelease` or `./gradlew bundleRelease` for AAB.
- Debug builds: `./gradlew assembleDebug`.

## Tests

```bash
./gradlew test                      # unit tests (JVM)
./gradlew connectedAndroidTest      # instrumented tests (requires connected device or emulator)
./gradlew lint                      # static analysis — run before every PR
```

All three must pass before marking a task complete. `lint` with zero errors is the bar — warnings that are not suppressed with a comment are not acceptable.

## Architecture

- Prefer **MVVM + Repository pattern**. ViewModels own UI state and expose it via `StateFlow` or `LiveData`. Repositories abstract data sources (network, database, cache).
- `ViewModel` scope: use `viewModelScope` for coroutines tied to UI lifecycle.
- Do not put business logic in `Activity` or `Fragment`. Activities and Fragments are views only.
- Single-Activity architecture with Jetpack Navigation is the default for new modules.

## Kotlin

- Prefer **coroutines** over callbacks. Suspend functions and `Flow` are the standard for async work.
- Use **`Flow`** for reactive streams — `StateFlow` for UI state, `SharedFlow` for one-shot events.
- Avoid `GlobalScope`. Scope coroutines to a lifecycle owner or `viewModelScope`/`lifecycleScope`.
- Prefer `data class` for models. Implement `equals`/`hashCode` via `data class`, not manually.
- Use `sealed class` or `sealed interface` for representing exhaustive state (Loading, Success, Error).
- Null safety: don't use `!!` unless you have a documented invariant proving non-null. Use `?.let`, `?: return`, or `requireNotNull` with a message.

## Dependencies

- Check for known CVEs before adding new dependencies: `./gradlew dependencyCheckAnalyze` (requires OWASP Dependency Check plugin).
- Pin dependency versions in `libs.versions.toml` (version catalog). Avoid dynamic versions (`+`).
- Update ProGuard / R8 rules in `proguard-rules.pro` whenever adding a library that uses reflection, serialization, or native code.

## Security

- Never commit `google-services.json` or keystore files (`.jks`, `.keystore`). Use CI secrets and environment variables for signing.
- API keys and secrets go in `local.properties` (already `.gitignored`) or CI environment, never in `BuildConfig` fields committed to source.
- Declare only the permissions your app actually uses in `AndroidManifest.xml`.

## Formatting and analysis

```bash
./gradlew ktlintCheck     # if ktlint is configured
./gradlew detekt          # if detekt is configured
./gradlew lint
```

## Adding a feature

1. Create a new module under `feature/<feature_name>/` or a package under `app/src/main/java/.../feature/<feature_name>/`.
2. Define the ViewModel, Repository interface, and data sources. Wire with Hilt (or manual DI if not using Hilt).
3. Add navigation destination to the nav graph.
4. Write unit tests for the ViewModel and Repository. Write at least one instrumented test for the main screen.
