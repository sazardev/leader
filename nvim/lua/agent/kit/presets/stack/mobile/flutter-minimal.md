<!-- name: Flutter minimal -->
<!-- desc: small apps without a state package: ValueNotifier/ChangeNotifier, ListenableBuilder, constructor DI -->

# STACK.md: Flutter minimal

## Summary

A small or medium Flutter app built only with what the SDK ships: state lives in `ChangeNotifier`/`ValueNotifier`
controllers, widgets listen with `ListenableBuilder`/`ValueListenableBuilder`, and dependencies are passed through
constructors (or one `InheritedNotifier` at the top). No state-management package, little code generation, fast builds
and a tiny dependency surface. When the app outgrows this (many shared async sources, complex caching), move to
Riverpod or Bloc deliberately.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Dart 3.5+ (records, patterns, sealed classes) | Expressive without codegen |
| Framework | Flutter (stable channel) | One codebase for every platform |
| State | `ChangeNotifier` / `ValueNotifier` controllers | In the SDK, simple, fast |
| Listening | `ListenableBuilder`, `ValueListenableBuilder` | Rebuild only the subtree that changes |
| DI | Constructor injection; one `InheritedNotifier`/`InheritedWidget` for app-wide services | Explicit, no service locator |
| Navigation | `Navigator` 2 via `go_router` only if deep links are needed, else `Navigator.push` | Smallest thing that works |
| Models | Plain immutable Dart classes with `copyWith`; records for small values | No codegen needed |
| HTTP | `package:http` | Small and enough for simple APIs |
| Storage | `shared_preferences` (settings), `sqflite`/`drift` only if data needs queries | Proportional to the need |
| Lint | `flutter_lints` + `strict-casts`, `strict-inference`, `strict-raw-types` | Strict without extra deps |
| Testing | `flutter_test` with hand-written fakes | Nothing else required |
| Deploy | Store builds | See the deploy add-on for the pipeline |

## Project layout

```
lib/
  main.dart                          builds services → AppScope → runApp
  app/
    app.dart                         MaterialApp, theme, routes
    app_scope.dart                   InheritedWidget exposing the services (api, storage, clock)
    theme.dart
  services/
    api_client.dart                  thin http wrapper: base URL, JSON, errors
    settings_store.dart              shared_preferences wrapper
  features/
    notes/
      note.dart                      immutable model + fromJson/toJson
      notes_repository.dart          abstract interface + http implementation
      notes_controller.dart          ChangeNotifier: state + methods (load, add, delete)
      notes_page.dart                creates/disposes the controller, ListenableBuilder
      widgets/note_tile.dart
test/                                mirrors lib/
```

Dependency direction: page → controller → repository interface ← implementation. Controllers import no widgets
(except `foundation.dart`); widgets never call repositories directly.

## Conventions

- One controller per screen; it owns the screen's state and is created and disposed by the page's `State`.
- Controller state is a single immutable value (a sealed class or a record) exposed as a getter; mutate by replacing it and calling `notifyListeners()` once.
- `ValueNotifier<T>` for one value; `ChangeNotifier` when a controller has several fields or methods.
- Rebuild narrowly: wrap only the part of the tree that depends on the notifier in `ListenableBuilder`.
- Async work: guard against `notifyListeners()` after `dispose()` (track a `_disposed` flag) and ignore stale results.
- Services are created once in `main.dart` and reached through `AppScope.of(context)` or passed down; no globals.
- No file over ~300 lines; extract widgets into `widgets/` as soon as a `build` method grows.

## Commands

| Task | Command |
| --- | --- |
| Install | `flutter pub get` |
| Run | `flutter run` |
| Test | `flutter test` |
| Lint | `flutter analyze` |
| Format | `dart format .` |
| Build | `flutter build apk --release` / `flutter build ipa` |

## Testing

- Controllers: plain unit tests with a fake repository; assert the state sequence by listening (`addListener`).
- Repositories: tests with `MockClient` from `package:http/testing.dart`.
- Widgets: pump the page with an `AppScope` holding fakes; assert loading, error, empty and loaded states.
- A bug fix starts with a failing test.

## Quality gates

- `flutter analyze` zero issues with the strict analyzer options; `dart format --set-exit-if-changed .`.
- `flutter test` passes; no package added without a written reason.

## Dependencies

- The point of this stack is few dependencies: SDK first, then `http`, `shared_preferences`, `go_router` when needed.
- Do NOT use: a state-management package (Provider, Riverpod, Bloc, GetX) — switching is a deliberate stack change; service locators (`get_it`); code generation for simple models; global mutable singletons.

## Rules for agents

- Never add a state-management or DI package; use ChangeNotifier/ValueNotifier and constructors.
- Every controller is disposed by the widget that created it.
- Never call `notifyListeners()` after `dispose()` or more than once per state change.
- Widgets never call repositories or `http` directly; controllers do.
- Keep models immutable; update state by replacing it, not by mutating lists in place.
- Rebuild the smallest subtree possible; never wrap a whole page in a builder for one field.
- Every screen handles loading, error (with retry) and empty states.
- If a change needs shared async caching across many screens, stop and propose the move to Riverpod instead of growing a homemade framework.
