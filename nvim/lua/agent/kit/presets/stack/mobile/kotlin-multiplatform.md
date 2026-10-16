<!-- name: Kotlin Multiplatform + Compose -->
<!-- desc: Shared Kotlin logic and Compose Multiplatform UI for Android and iOS: Ktor, SQLDelight, Koin -->

# STACK.md: Kotlin Multiplatform + Compose Multiplatform

## Summary

One Kotlin codebase for Android and iOS: domain, data and presentation logic live in `commonMain`; the UI is Compose
Multiplatform, with platform code only where a platform API is needed (`expect`/`actual`). Networking with Ktor, local data
with SQLDelight, dependency injection with Koin, unidirectional state with ViewModels exposing `StateFlow`.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Kotlin 2.1+ (K2 compiler) | One language for both platforms |
| Shared logic | Kotlin Multiplatform (`commonMain`, `androidMain`, `iosMain`) | Share everything but platform APIs |
| UI | Compose Multiplatform | One UI toolkit |
| Navigation | Navigation Compose (multiplatform) | Type-safe routes |
| State | `androidx.lifecycle` ViewModel (multiplatform) + `StateFlow` | UDF |
| Networking | Ktor client + kotlinx.serialization | Multiplatform HTTP |
| Local data | SQLDelight | Typed SQL on both platforms |
| DI | Koin | Multiplatform, simple |
| Testing | kotlin.test + Turbine + Ktor MockEngine | Shared tests |
| Lint | ktlint + detekt | Style and smells |
| Build | Gradle (Kotlin DSL, version catalog) | Standard |

## Project layout

```
composeApp/src/
  commonMain/kotlin/app/
    App.kt                         root composable + navigation
    di/AppModule.kt                Koin modules
    core/
      network/HttpClientFactory.kt
      database/DatabaseFactory.kt  expect
    features/
      notes/
        domain/Note.kt
        domain/NotesRepository.kt  interface
        data/NotesRepositoryImpl.kt Ktor + SQLDelight
        data/NoteDto.kt
        ui/NotesViewModel.kt       StateFlow<NotesState>
        ui/NotesScreen.kt
        ui/NotesState.kt
  commonMain/sqldelight/app/Notes.sq
  androidMain/kotlin/app/core/database/DatabaseFactory.android.kt  actual
  iosMain/kotlin/app/core/database/DatabaseFactory.ios.kt          actual
  commonTest/kotlin/app/features/notes/NotesViewModelTest.kt
iosApp/                            Xcode project hosting the shared framework
gradle/libs.versions.toml
```

Dependency direction: `ui → domain ← data`; features never import each other; platform source sets only implement `expect`s.

## Conventions

- Screens take a state and an `onEvent` lambda; ViewModels own state and expose `StateFlow`.
- Everything in `commonMain` unless a platform API forces `expect`/`actual`.
- Repositories return domain types; DTOs stay in `data/`.
- Dispatchers injected, never hard-coded, so tests control them.

## Commands

| Task | Command |
| --- | --- |
| Android run | `./gradlew :composeApp:installDebug` |
| iOS | open `iosApp/iosApp.xcodeproj` and run |
| Test | `./gradlew allTests` |
| Lint | `./gradlew ktlintCheck detekt` |
| Build | `./gradlew build` |

## Testing

- ViewModels in `commonTest` with Turbine; repositories with Ktor `MockEngine` and an in-memory SQLDelight driver.
- One UI test per main screen (Compose UI test on Android).

## Quality gates

- `./gradlew build allTests ktlintCheck detekt` green; no warnings in shared code.

## Dependencies

- Versions in `libs.versions.toml` only.
- Do NOT use: Android-only libraries in `commonMain`, platform UI duplicated per platform without reason, GlobalScope.

## Rules for agents

- Put new code in `commonMain` first; add `expect`/`actual` only for platform APIs.
- Never call network or database from a composable; go through the ViewModel.
- Expose immutable state (`StateFlow<State>`), update with `update { }`.
- Add dependencies to the version catalog, not inline.
- Keep composables stateless and previewable; hoist state.
- Write the shared test before the shared logic.
- Use kotlinx.serialization DTOs and map them to domain types.
- Keep platform source sets thin.
