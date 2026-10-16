<!-- name: SwiftUI -->
<!-- desc: native iOS: SwiftUI, Swift 6 concurrency, @Observable, SPM feature modules, SwiftData, swift-testing -->

# STACK.md: SwiftUI

## Summary

A native iOS (and iPadOS/macOS where it applies) app with SwiftUI and Swift 6 strict concurrency. The app target is a thin
shell; features live in local Swift packages, one module per feature plus core modules, so boundaries are enforced by the
compiler. Views read `@Observable` models; side effects live in services behind protocols injected from the app's
composition root.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Swift 6 (strict concurrency, typed throws where useful) | Data-race safety at compile time |
| UI | SwiftUI (iOS 17+ minimum) | Declarative, Observation, NavigationStack |
| State | Observation (`@Observable`, `@State`, `@Environment`) | No Combine boilerplate |
| Navigation | `NavigationStack` with typed path / router per feature | Deep links, state restoration |
| Modules | Swift Package Manager local packages | Compiler-enforced boundaries, fast builds |
| Persistence | SwiftData (or GRDB for complex SQL) | Native models / explicit SQL |
| Networking | `URLSession` async/await + `Codable` | No dependency needed |
| Secrets | Keychain wrapper | Tokens never in UserDefaults |
| Testing | swift-testing (`@Test`, `#expect`), XCTest for UI tests | Modern, parallel |
| Snapshots | `pointfreeco/swift-snapshot-testing` (optional) | Visual regressions |
| Lint/format | SwiftLint + `swift-format` (or SwiftFormat) | Consistent style |
| CI/CD | Xcode Cloud or GitHub Actions + fastlane | Signed builds, TestFlight |
| Monitoring | MetricKit + Sentry or Crashlytics | Crashes, hangs |

## Project layout

```
App/
  MyApp.swift                      @main, composition root: builds services, injects into environment
  RootView.swift
Packages/
  Core/
    Sources/Networking/APIClient.swift        protocol + URLSession implementation
    Sources/Networking/Endpoint.swift
    Sources/Persistence/                      SwiftData container, migrations
    Sources/DesignSystem/                     colors, typography, components (one per file)
    Sources/Models/                           shared domain types
  Features/
    Orders/
      Sources/Orders/
        Domain/Order.swift                    value types
        Domain/OrdersRepository.swift         protocol
        Data/RemoteOrdersRepository.swift     implementation (APIClient)
        Presentation/OrdersListView.swift
        Presentation/OrdersListModel.swift    @Observable @MainActor model
        Presentation/OrderRow.swift
      Tests/OrdersTests/
    Profile/...
  Package.swift                    products: one library per feature
AppUITests/
```

Dependency direction: `App → Features → Core`. Features never import each other; cross-feature navigation goes through the app's router. `Domain` folders import only Foundation.

## Conventions

- One type per file; views over ~150 lines are split into subviews (structs), not computed properties.
- View models are `@Observable @MainActor final class`; views own them with `@State`, receive dependencies by init.
- Services and repositories are protocols (`Sendable`), implementations are actors or `Sendable` structs.
- All async work uses structured concurrency (`async let`, `TaskGroup`, `.task {}` modifiers); no detached tasks without a reason.
- Errors are typed enums conforming to `LocalizedError`; views show `errorDescription`.
- Strings in String Catalogs (`Localizable.xcstrings`); colors and fonts from DesignSystem.
- `#Preview` for every view with sample data, in light/dark and dynamic type sizes.
- New feature = new package target `Features/<Name>` with Domain/Data/Presentation + tests + route in the app.

## Commands

| Task | Command |
| --- | --- |
| Build | `xcodebuild -scheme App -destination 'platform=iOS Simulator,name=iPhone 16' build` |
| Test | `xcodebuild test -scheme App -destination 'platform=iOS Simulator,name=iPhone 16'` |
| Test a package | `swift test --package-path Packages/Features/Orders` |
| Lint | `swiftlint --strict` |
| Format | `swift format --in-place --recursive App Packages` |
| Resolve packages | `xcodebuild -resolvePackageDependencies` |
| Beta | `fastlane beta` |

## Testing

- Domain and view models with swift-testing, repositories replaced by in-memory fakes conforming to the protocols.
- Networking with a `URLProtocol` stub; decoding tests from JSON fixtures.
- Persistence tests with an in-memory `ModelContainer`.
- UI tests (XCUITest) only for critical flows; accessibility identifiers on interactive elements.
- Snapshot tests for DesignSystem components in light/dark and large dynamic type.

## Quality gates

- Builds with Swift 6 language mode, zero warnings (`SWIFT_TREAT_WARNINGS_AS_ERRORS = YES` in CI).
- SwiftLint `--strict` and the formatter clean; all tests pass.
- No force unwraps (`!`) or `try!` outside tests; no `@unchecked Sendable` without a comment explaining the safety.

## Dependencies

- Apple frameworks first (URLSession, SwiftData, Observation, OSLog).
- Third-party only through SPM, pinned to minor versions, wrapped behind a protocol.
- Do NOT use: CocoaPods for new dependencies, Combine for new state (use Observation/async), `ObservableObject` in new code, singletons for services, Alamofire (URLSession is enough).

## Rules for agents

- Never put networking or persistence calls in a View; they go through the model and a protocol.
- Mark UI-facing models `@MainActor`; never hop to the main thread with `DispatchQueue.main` in new code.
- Never add a cross-feature import; add a route or move the shared type to Core.
- Every view gets a `#Preview`; every new public type in a package gets tests.
- Use `.task` (cancelled automatically) instead of `Task {}` in `onAppear`.
- All user-facing text in String Catalogs; all colors/fonts from DesignSystem.
- Support Dynamic Type and VoiceOver: labels on icon-only buttons, no fixed font sizes.
- Keep `MyApp.swift` the only place that instantiates concrete services.
