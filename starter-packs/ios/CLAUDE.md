# iOS Project

## Stack

iOS (Swift). Check the Xcode project or `Package.swift` for deployment target, Swift version, and key dependencies.

## Build

- Use `xcodebuild` for CI and scripted builds. Use `swift build` for Swift Package Manager projects.
- Never invoke the Swift compiler directly — always go through the build system.
- Archive for distribution: `xcodebuild archive -scheme <Scheme> -archivePath build/<Scheme>.xcarchive`.

## Tests

```bash
# Unit and UI tests via xcodebuild
xcodebuild test \
  -scheme <YourScheme> \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -resultBundlePath TestResults
```

Run tests before every PR. All tests must pass. No skipped tests without a documented reason.

## Architecture

- **SwiftUI**: prefer `@Observable` (iOS 17+) over `@ObservedObject`/`@StateObject` for new code. For targets below iOS 17, use `@StateObject` for owned objects, `@ObservedObject` for injected ones.
- Separate data fetching and business logic from views. Views should only call methods on their view model or environment objects — no direct network calls from SwiftUI body.
- Use the **Repository pattern** to abstract data sources (network, persistence, cache).
- Prefer `async/await` (Swift Concurrency) over `DispatchQueue` or completion handlers for all new async code.

## Swift

- **Concurrency**: mark all async work with `async throws`. Use `Task` for fire-and-forget from synchronous contexts. Use `MainActor` for UI updates, not `DispatchQueue.main.async`.
- **Memory**: avoid retain cycles. Use `[weak self]` or `[unowned self]` in closures that could outlive their owner. Mark `unowned` only when the lifetime is guaranteed shorter.
- **Optionals**: prefer `guard let` / `if let` over force-unwrap (`!`). Force-unwrap requires a comment explaining the invariant.
- Use `struct` for value types (models, view state). Use `class` only when identity or shared mutable state is required.
- Prefer `enum` with associated values for exhaustive state representation (loading, success, failure).

## Privacy and permissions

- Declare every permission key in `Info.plist` before writing the code that uses the API (e.g., `NSCameraUsageDescription` before calling `AVCaptureSession`).
- Request permissions at the moment they are needed, not at launch.
- Review `AppPrivacyInfo.xcprivacy` (required for App Store submissions as of iOS 17.5+) when adding SDKs that access protected APIs.

## Signing and secrets

- Never commit `.p12` certificates, `.mobileprovision` profiles, or API keys to source control.
- Use CI environment variables or Xcode Cloud secrets for signing credentials.
- Use `xcconfig` files (not committed) or environment variables for scheme-specific configuration (API base URLs, feature flags).

## Localization

- All user-facing strings through `NSLocalizedString` (or `String(localized:)` in Swift 5.9+). No hardcoded English strings in the UI.
- Keep `Localizable.strings` sorted alphabetically.

## Formatting and analysis

```bash
swiftlint                  # if SwiftLint is configured
swift-format lint --recursive .   # if swift-format is configured
```

## Adding a feature

1. Create a new group under `Features/<FeatureName>/` with subgroups: `Model`, `ViewModel`, `View`.
2. Define the data model as a `struct`. Wire the view model with `@Observable` (iOS 17+) or `@StateObject`.
3. Add navigation from the relevant coordinator or `NavigationStack`.
4. Write unit tests for the view model and repository. Write at least one UI test for the happy path.
