<!-- name: Flutter + Bloc -->
<!-- desc: Flutter with flutter_bloc/Cubit, constructor DI (get_it optional), go_router, freezed, dio, bloc_test -->

# STACK.md: Flutter + Bloc

## Summary

A Flutter app where every screen's state lives in a Bloc or Cubit: UI widgets only render states and send events.
Feature-first clean architecture: `domain` (entities, repository interfaces, use cases) knows nothing about Flutter,
dio or JSON; `data` implements the repositories; `presentation` holds blocs and widgets. Blocs are explicit, testable
state machines, which suits teams that want predictable, reviewable state transitions.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Dart 3.5+ (sealed classes, records, patterns) | Exhaustive `switch` over states and events |
| Framework | Flutter (stable channel) | One codebase for Android and iOS |
| State | `flutter_bloc` + `bloc` (Cubit for simple screens, Bloc when events matter) | Explicit state machines, great tooling, `bloc_test` |
| DI | Constructor injection wired in `app/di.dart`; `get_it` (+ `injectable`) only when the graph grows | Explicit dependencies, no hidden globals in widgets |
| Navigation | `go_router` | Declarative routes, deep links, auth redirects |
| Models | `freezed` + `json_serializable` | Immutable states, events and DTOs with `copyWith` |
| HTTP | `dio` with interceptors (auth, retry, logging) | Cancellation, interceptors, multipart |
| Local storage | `shared_preferences` (flags), `drift` (data), `flutter_secure_storage` (tokens) | Right store per kind of data |
| i18n | `flutter_localizations` + `intl` + ARB (`gen-l10n`) | Official, generated, type-safe |
| Lint | `very_good_analysis` | Strict static analysis |
| Testing | `flutter_test`, `bloc_test`, `mocktail`, golden tests, `integration_test` | Blocs tested as input → states |
| Codegen | `build_runner` | One command for freezed, json and injectable |
| Deploy | Store builds per flavor (dev/prod) | See the deploy add-on for the pipeline |

## Project layout

```
lib/
  main_dev.dart / main_prod.dart        entry per flavor: config → di → runApp
  app/
    app.dart                            MaterialApp.router, theme, localization, top-level BlocProviders
    di.dart                             the composition root: builds clients, repositories, blocs
    router.dart                         go_router config and redirects (reads AuthBloc state)
    theme/                              ThemeData, color scheme, spacing tokens
  core/
    network/dio_client.dart             Dio factory + interceptors (one interceptor per file)
    error/failure.dart                  sealed Failure hierarchy
    widgets/                            app-wide widgets, one per file
  features/
    orders/
      domain/
        order.dart                      entity (freezed)
        orders_repository.dart          abstract interface class
        get_orders.dart                 use case (one per file, only when it adds logic)
      data/
        order_dto.dart                  JSON DTO + toDomain()
        orders_api.dart                 remote source (dio)
        orders_repository_impl.dart     implements the domain interface, maps errors to Failure
      presentation/
        orders_page.dart                BlocProvider + view
        orders_view.dart                BlocBuilder/BlocListener, no logic
        bloc/
          orders_bloc.dart              events → states
          orders_event.dart             sealed events
          orders_state.dart             sealed / freezed states
        widgets/order_tile.dart
  l10n/app_en.arb
test/                                   mirrors lib/
integration_test/
```

Dependency direction: `presentation → domain ← data`. `domain` imports no Flutter, no dio, no `bloc`. A bloc talks to
repositories (or use cases) through their interfaces only. Features never import another feature's `data` or `presentation`.

## Conventions

- One bloc per screen or flow; one file each for bloc, events and states. A Cubit becomes a Bloc when event transformers (debounce, droppable) are needed.
- States are sealed classes (`OrdersInitial`, `OrdersLoading`, `OrdersLoaded`, `OrdersFailure`) or one freezed state with a status enum; never booleans like `isLoading` + `hasError` side by side.
- Widgets: `XPage` provides the bloc, `XView` renders; `BlocListener` for side effects (navigation, snackbars), `BlocBuilder` with `buildWhen` for rendering.
- Repositories return `Result`-style values or throw typed `Failure`s; blocs never catch `DioException` directly.
- Event concurrency is explicit with `bloc_concurrency` transformers (`droppable`, `restartable`, `sequential`).
- Files are `snake_case.dart`, ~300 lines max; split a widget when its `build` stops fitting on a screen.
- New feature = domain entity + repository interface → DTO + API + repository impl → bloc (events/states) → page/view → route → tests.

## Commands

| Task | Command |
| --- | --- |
| Install | `flutter pub get` |
| Run (dev flavor) | `flutter run --flavor dev -t lib/main_dev.dart` |
| Generate | `dart run build_runner build --delete-conflicting-outputs` |
| Watch codegen | `dart run build_runner watch --delete-conflicting-outputs` |
| Test | `flutter test` |
| Golden update | `flutter test --update-goldens` |
| Lint | `flutter analyze` |
| Format | `dart format .` |
| Integration tests | `flutter test integration_test` |

## Testing

- Blocs: `blocTest` for every event: seed state → act → expected sequence of states; repositories faked with `mocktail`.
- Repositories: unit tests with a mocked `Dio` (or `http_mock_adapter`) covering success, error mapping and DTO parsing.
- Widgets: pump the view with a `MockBloc` (`whenListen`) and assert per state; golden tests for key screens.
- Integration tests for the critical flows (login, the main task) on a real device or emulator in CI.
- A bug fix starts with a failing `blocTest` or widget test.

## Quality gates

- `flutter analyze` with `very_good_analysis` has zero issues; `dart format --set-exit-if-changed .` passes.
- `flutter test` passes; generated files are up to date (CI runs build_runner and diffs).
- No `print`; logging goes through one logger; no `// ignore:` without a reason on the same line.

## Dependencies

- Allowed: the table above. A new package needs a reason (maintenance, size, platform support) in the PR.
- Do NOT use: Provider/Riverpod/GetX alongside Bloc (one state approach), `setState` for anything shared, `http` next to dio, service locators read from inside widgets (`GetIt.I` in `build`), code generation for mocks (`mockito` builders).

## Rules for agents

- Never import `package:flutter`, `dio` or `bloc` in a `domain/` file.
- Never edit `*.g.dart`, `*.freezed.dart` or `*.config.dart`: change the source and run build_runner.
- Every state class is immutable; every new event has a `blocTest`.
- Never emit after the bloc is closed or from a stream without `emit.forEach`/`emit.onEach`.
- Side effects (navigation, dialogs, snackbars) live in `BlocListener`, never in `BlocBuilder`.
- Every user-facing string goes in the ARB files; colors, text styles and spacings come from the theme.
- Every screen handles loading, failure (with retry) and empty states.
- Wire new dependencies in `app/di.dart` only; no `GetIt.I` calls inside widgets or blocs.
- Use `context.read` for events and `context.select`/`BlocSelector` to rebuild only what changed.
