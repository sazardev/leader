<!-- name: Flutter + Riverpod -->
<!-- desc: Flutter app: Riverpod (generator), go_router, freezed, dio; feature-first clean architecture -->

# STACK.md: Flutter + Riverpod

## Summary

A cross-platform Flutter app (iOS, Android, optionally web/desktop) organised feature-first. Each feature has three layers:
`domain` (entities, repository interfaces, use cases; pure Dart), `data` (DTOs, data sources, repository implementations)
and `presentation` (widgets, controllers). Riverpod is the dependency injection and state container; code generation
(riverpod_generator, freezed, json_serializable) removes boilerplate and keeps state immutable.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Dart 3.5+ (sound null safety, records, patterns, sealed classes) | Exhaustive `switch` over states and errors |
| Framework | Flutter (stable channel) | One codebase, native performance |
| State / DI | `flutter_riverpod` + `riverpod_annotation` + `riverpod_generator` | Compile-safe providers, auto-dispose, testable overrides |
| Navigation | `go_router` (+ `go_router_builder` for typed routes) | Declarative, deep links, redirects for auth |
| Models | `freezed` + `json_serializable` | Immutable data classes, unions, `copyWith`, JSON |
| HTTP | `dio` + interceptors (auth, retry, logging) | Cancellation, interceptors, multipart |
| Local storage | `shared_preferences` (flags) / `drift` (SQLite, data) / `flutter_secure_storage` (tokens) | Right tool per kind of data |
| i18n | `flutter_localizations` + `intl` + ARB files (`gen-l10n`) | Official, generated, type-safe |
| Lint | `very_good_analysis` (or `flutter_lints` with strict-casts/inference/raw-types) | Strict static analysis |
| Testing | `flutter_test`, `mocktail`, golden tests (`alchemist` optional), `integration_test` | No codegen mocks |
| Codegen | `build_runner` | One `dart run build_runner` for all generators |
| Monitoring | `sentry_flutter` or Firebase Crashlytics | Crash and error reporting |
| CI/CD | GitHub Actions + `fastlane` or Codemagic | Signed builds per flavor |

## Project layout

```
lib/
  main_dev.dart / main_prod.dart      entry per flavor: config + ProviderScope + App
  app/
    app.dart                          MaterialApp.router, theme, localization
    router.dart                       go_router config, redirects, typed routes
    theme/                            ThemeData, color scheme, text theme, spacing tokens
  core/
    network/dio_client.dart           Dio provider + interceptors (one interceptor per file)
    error/failure.dart                sealed Failure hierarchy
    storage/                          secure storage, preferences wrappers
    widgets/                          app-wide reusable widgets (one widget per file)
  features/
    orders/
      domain/
        order.dart                    entity (freezed)
        order_repository.dart         abstract interface class
        place_order.dart              use case (one per file)
      data/
        order_dto.dart                JSON DTO + toDomain()
        orders_api.dart               remote data source (dio)
        order_repository_impl.dart    implements the domain interface
      presentation/
        orders_page.dart              screen (ConsumerWidget)
        orders_controller.dart        @riverpod AsyncNotifier
        widgets/order_tile.dart       feature widgets
  l10n/app_en.arb
test/                                 mirrors lib/ (features/orders/...)
integration_test/                     end-to-end flows
```

Dependency direction: `presentation → domain ← data`. `domain` imports no Flutter, no dio, no data classes. Features never import another feature's `data` or `presentation`; shared things move to `core`.

## Conventions

- One file = one public class/widget/provider. Widgets over ~150 lines are split into smaller widgets (not helper methods returning widgets).
- Providers are generated (`@riverpod`), never hand-written globals; UI reads with `ref.watch`, actions use `ref.read(...notifier)`.
- Async state is `AsyncValue<T>`; screens render it with an exhaustive `switch` (data / loading / error).
- Errors: data layer catches `DioException` and maps to a sealed `Failure`; domain and UI never see transport exceptions.
- Entities and states are immutable (freezed); never mutate a list in place, return a new state.
- Route paths and parameters only through typed routes; no string paths scattered in widgets.
- `const` constructors everywhere possible; keys only where identity matters.
- New feature = `features/<name>/{domain,data,presentation}` + provider wiring + route + ARB strings + tests.

## Commands

| Task | Command |
| --- | --- |
| Install | `flutter pub get` |
| Generate | `dart run build_runner build --delete-conflicting-outputs` |
| Generate (watch) | `dart run build_runner watch --delete-conflicting-outputs` |
| Run | `flutter run --flavor dev -t lib/main_dev.dart` |
| Test | `flutter test` |
| Goldens update | `flutter test --update-goldens --tags golden` |
| Integration | `flutter test integration_test` |
| Lint | `flutter analyze` |
| Format | `dart format .` |
| L10n | `flutter gen-l10n` |
| Build | `flutter build appbundle --flavor prod -t lib/main_prod.dart` / `flutter build ipa ...` |

## Testing

- Domain use cases: pure Dart unit tests with `mocktail` fakes of repositories.
- Controllers: `ProviderContainer` with `overrides` for repositories; assert the sequence of `AsyncValue` states.
- Repositories: unit tests with a mocked Dio adapter (or `http_mock_adapter`), covering error mapping to `Failure`.
- Widgets: `pumpWidget` inside `ProviderScope(overrides: ...)`; find by key/semantics, not by text when text is localized.
- Golden tests for design-system widgets and key screens in light/dark and two text scales.
- `integration_test` for the critical flows (login, main purchase/creation flow). Coverage target: domain and data ≥ 80%.

## Quality gates

- `flutter analyze` with zero issues under `very_good_analysis`; `dart format --set-exit-if-changed .`.
- `flutter test` passes, goldens unchanged unless the PR updates them on purpose.
- Generated files (`*.g.dart`, `*.freezed.dart`) are committed and CI fails if `build_runner` produces a diff.
- No `print` (use a logger), no `dynamic` without a comment, no `!` on values that can be null in practice.

## Dependencies

- Prefer Flutter/Dart team and well-maintained packages (pub points ≥ 130, recent releases, null-safe).
- Each new package needs a reason in the PR; wrappers in `core/` isolate third-party APIs.
- Do NOT use: GetX (mixes routing, DI and state with global magic), `provider` alongside Riverpod, `setState` for shared state, `mockito` (codegen mocks), `http` in parallel with dio, service locators like `get_it` (Riverpod is the DI).

## Rules for agents

- Never import `package:flutter` or `dio` in a `domain/` file.
- Never edit `*.g.dart` or `*.freezed.dart`: change the source and run build_runner.
- Every provider is generated with `@riverpod`; keepAlive only with a comment saying why.
- Every user-facing string goes in the ARB files; no hardcoded text in widgets.
- Colors, text styles and spacings come from the theme/tokens, never literals in widgets.
- Every screen handles loading, error (with retry) and empty states.
- Do not put logic in `build()`: derive it in the controller or a provider.
- A new repository method comes with a test of its error mapping.
- Cancel requests and subscriptions on dispose (`ref.onDispose`, `CancelToken`).
