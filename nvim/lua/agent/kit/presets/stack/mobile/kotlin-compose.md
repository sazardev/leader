<!-- name: Kotlin + Jetpack Compose -->
<!-- desc: native Android: Compose, MVVM/UDF, Hilt, Room, Retrofit, type-safe navigation, multi-module -->

# STACK.md: Kotlin + Jetpack Compose

## Summary

A native Android app following Google's recommended architecture: UI layer (Compose + ViewModel exposing `StateFlow`
of immutable UI state, unidirectional data flow), optional domain layer (use cases), data layer (repositories over Room
and the network). Multi-module: `core:*` modules shared, one `feature:*` module per feature, the `app` module wires
everything. Gradle convention plugins keep module setup in one place.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Kotlin 2.x (K2 compiler) | Coroutines, null safety |
| UI | Jetpack Compose (BOM) + Material 3 | Declarative UI |
| Architecture | ViewModel + `StateFlow` + UDF | Lifecycle-aware, testable |
| DI | Hilt (KSP) | Standard Android DI |
| Navigation | Navigation Compose with type-safe routes (`@Serializable`) | Compile-checked arguments |
| Database | Room (KSP) + Flow queries | Reactive local source of truth |
| Network | Retrofit + OkHttp + kotlinx.serialization (or Ktor client) | Mature, typed |
| Async | Coroutines + Flow | Structured concurrency |
| Preferences | DataStore | Async, safe replacement of SharedPreferences |
| Images | Coil 3 | Compose-first |
| Build | Gradle Kotlin DSL + version catalog (`libs.versions.toml`) + convention plugins | One source of versions |
| Testing | JUnit 5 (or 4), Turbine, MockK, kotlinx-coroutines-test, Compose UI tests, Robolectric | Flow and UI tests |
| Lint/format | detekt + ktlint (Spotless) + Android Lint | Strict static checks |
| Monitoring | Firebase Crashlytics or Sentry | Crash reporting |

## Project layout

```
app/                                   Application, MainActivity, NavHost, Hilt entry points
build-logic/convention/                Gradle convention plugins (android-library, feature, compose)
core/
  model/                               plain Kotlin domain models
  data/                                repositories (interfaces + implementations)
  database/                            Room database, DAOs, entities
  network/                             Retrofit services, DTOs, interceptors
  designsystem/                        theme, tokens, reusable composables
  common/                              dispatchers, result types
  testing/                             fakes, test rules
feature/
  orders/
    src/main/.../orders/
      OrdersRoute.kt                   type-safe route + NavGraphBuilder extension
      OrdersScreen.kt                  stateless composable (state in, events out)
      OrdersViewModel.kt               @HiltViewModel, StateFlow<OrdersUiState>
      OrdersUiState.kt                 sealed interface Loading/Success/Error
      components/OrderItem.kt
    src/test/ ...                      ViewModel tests
    src/androidTest/ ...               Compose UI tests
gradle/libs.versions.toml
```

Dependency direction: `app → feature:* → core:data → core:database/core:network → core:model`. Feature modules never depend on each other; navigation between them goes through `app`.

## Conventions

- One public class or composable per file; screens split into a stateful `XRoute` (collects ViewModel) and a stateless `XScreen`.
- UI state is an immutable data class or sealed interface; ViewModels expose `StateFlow`, collected with `collectAsStateWithLifecycle()`.
- Events flow up as lambdas; no ViewModel passed into child composables.
- Repositories are the single source of truth: Room first, network refreshes the database.
- Dispatchers are injected (`@IoDispatcher`); never hardcode `Dispatchers.IO` in classes.
- Errors are modelled (`Result` / sealed errors) and mapped to UI messages in the ViewModel.
- Strings in `strings.xml`; dimensions and colors from the design system.
- New feature = `feature:<name>` module via the convention plugin + route + ViewModel + tests.

## Commands

| Task | Command |
| --- | --- |
| Build | `./gradlew assembleDebug` |
| Unit tests | `./gradlew testDebugUnitTest` |
| UI tests | `./gradlew connectedDebugAndroidTest` |
| Lint | `./gradlew detekt lintDebug` |
| Format | `./gradlew spotlessApply` |
| Dependency updates | `./gradlew dependencyUpdates` (versions plugin) |
| Release | `./gradlew bundleRelease` |

## Testing

- ViewModels: kotlinx-coroutines-test (`runTest`, `StandardTestDispatcher`) with fake repositories; assert state sequences with Turbine.
- Repositories: in-memory Room database + MockWebServer for the network.
- Composables: `createComposeRule()` tests on stateless screens with fixed state; Robolectric for fast JVM UI tests.
- Prefer fakes from `core:testing` over mocks; MockK only at third-party boundaries.
- Screenshot tests (Roborazzi or Paparazzi) for the design system.

## Quality gates

- detekt, ktlint and Android Lint with zero issues (baseline only for legacy code, never grows).
- Unit tests pass; UI tests pass on CI emulator for critical flows.
- `allWarningsAsErrors = true` for Kotlin; R8 enabled in release with keep rules tested.
- Compose compiler stability reports checked for hot screens.

## Dependencies

- All versions in `libs.versions.toml`; AndroidX and Kotlin libraries first.
- Do NOT use: LiveData in new code (use StateFlow), RxJava, Dagger without Hilt, Gson (use kotlinx.serialization), `GlobalScope`, `SharedPreferences` for new data, XML layouts for new screens.

## Rules for agents

- Never call repositories from composables; only ViewModels touch the data layer.
- Never add a dependency between two `feature:*` modules.
- Never launch coroutines outside `viewModelScope` or an injected scope.
- Every new screen: stateless `Screen` composable + `@Preview` + UI state sealed interface + ViewModel test.
- Every Room schema change gets a migration and a migration test; schema JSON exported and committed.
- Versions only in the version catalog, never inline in a build file.
- Use type-safe routes; no string route templates.
- Every clickable element has a content description or visible text; touch targets ≥ 48dp.
