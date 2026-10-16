<!-- name: Flutter desktop -->
<!-- desc: Flutter for macOS/Windows/Linux: window_manager, menus, Shortcuts/Actions, adaptive layouts, packaging -->

# STACK.md: Flutter desktop

## Summary

A desktop application for macOS, Windows and Linux built with Flutter. It behaves like a native desktop app: real menus,
keyboard shortcuts for every command, resizable multi-pane layouts, hover and right-click, file dialogs and drag-and-drop.
Commands are modelled once (Intents + Actions) and exposed through menus, shortcuts and a command palette. Feature-first
layout; platform code is isolated behind interfaces.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Dart 3.5+ | Sealed classes, patterns |
| Framework | Flutter desktop (stable channel) | One codebase, three desktop platforms |
| Window | `window_manager` (+ `screen_retriever`) | Size, position, title bar, min size, close interception |
| Menus | `PlatformMenuBar` on macOS, in-app `MenuBar` on Windows/Linux | Native menu where the OS expects one |
| Commands | `Shortcuts` + `Actions` + `Intent`s, one command palette | Every command reachable from the keyboard |
| State | `flutter_riverpod` + `riverpod_generator` | Scoped state per window/pane |
| Files | `file_selector`, `desktop_drop`, `path_provider` | Native dialogs, drag-and-drop, app dirs |
| Settings | JSON file in the app support dir (or `drift` for data) | Inspectable, versioned settings |
| Models | `freezed` + `json_serializable` | Immutable state and settings |
| Lint | `very_good_analysis` | Strict analysis |
| Testing | `flutter_test`, `mocktail`, golden tests, `integration_test` on each OS | Keyboard flows tested |
| Packaging | `msix` (Windows), signed + notarized `.dmg` (macOS), AppImage/Flatpak (Linux) | Native installers |
| Deploy | GitHub Releases per platform; auto-update optional (`auto_updater`) | See the deploy add-on for the pipeline |

## Project layout

```
lib/
  main.dart                          windowManager.ensureInitialized → window options → runApp
  app/
    app.dart                         MaterialApp, theme (desktop density), Shortcuts/Actions root
    commands/
      intents.dart                   one Intent per command (NewDocumentIntent, SaveIntent…)
      shortcuts.dart                 platform-aware bindings (Cmd on macOS, Ctrl elsewhere)
      command_palette.dart           searchable list of every command
    menus/app_menu.dart              PlatformMenuBar / MenuBar built from the same commands
    window/window_controller.dart    size, position persistence, close confirmation
  core/
    platform/file_service.dart       interface; file_selector implementation in file_service_impl.dart
    settings/settings_repository.dart
  features/
    editor/
      domain/document.dart
      data/document_repository.dart  read/write files
      presentation/editor_pane.dart
      presentation/editor_actions.dart   Actions bound to the editor's intents
    sidebar/…
macos/ windows/ linux/               runners (entitlements, Info.plist, manifest)
test/
integration_test/
```

Dependency direction: `presentation → domain ← data`; `core/platform` hides plugins behind interfaces so features never
import a plugin directly. Commands (intents) are defined once in `app/commands` and reused by menus, shortcuts and palette.

## Conventions

- Every user action is an `Intent` with an `Action`; menus, shortcuts and buttons invoke the intent, never the logic directly.
- Shortcuts follow the platform: `Cmd` on macOS, `Ctrl` on Windows/Linux, built with `SingleActivator(meta:/control:)` in one place.
- Layouts adapt by window width (compact < 600, medium < 1000, expanded); panes are resizable and their sizes persisted.
- Every interactive widget has hover, focus and pressed states and a visible keyboard focus; context menus on right-click.
- Window size/position and settings persist in the platform's app support directory, versioned with a schema number.
- Long work runs in isolates (`Isolate.run`) so the UI never freezes.
- Platform-specific code lives behind `core/platform` interfaces with one implementation per platform when they differ.

## Commands

| Task | Command |
| --- | --- |
| Install | `flutter pub get` |
| Run (macOS) | `flutter run -d macos` |
| Run (Windows) | `flutter run -d windows` |
| Run (Linux) | `flutter run -d linux` |
| Generate | `dart run build_runner build --delete-conflicting-outputs` |
| Test | `flutter test` |
| Integration tests | `flutter test integration_test -d <macos|windows|linux>` |
| Lint | `flutter analyze` |
| Format | `dart format .` |
| Build | `flutter build macos` / `flutter build windows` / `flutter build linux` |
| Package Windows | `dart run msix:create` |

## Testing

- Unit tests for repositories and controllers; Actions tested by invoking intents on a test widget tree.
- Widget tests drive keyboard shortcuts (`tester.sendKeyDownEvent`) for every command.
- Golden tests per layout breakpoint (compact, medium, expanded) and light/dark.
- Integration tests run on each OS in CI (macOS, Windows, Linux runners).

## Quality gates

- `flutter analyze` zero issues; `dart format --set-exit-if-changed .`.
- `flutter test` passes; the app builds on all three platforms in CI.
- Every command in `intents.dart` is reachable from a shortcut or the menu (a test enumerates them).

## Dependencies

- Allowed: the table above. A plugin must support all three desktop platforms or sit behind an interface with a fallback.
- Do NOT use: mobile-only plugins without desktop support, `dart:io` `Process` calls scattered in features (wrap them in `core/platform`), webview-based UIs for core screens, hardcoded `Ctrl` shortcuts.

## Rules for agents

- Every new command is an Intent + Action, added to the menu, the shortcuts table and the command palette.
- Never import a plugin from a feature: go through `core/platform` interfaces.
- Never block the UI isolate with file or CPU work; use `Isolate.run` or async IO.
- Use platform-correct modifiers; never hardcode `Ctrl` for macOS.
- Every interactive element is keyboard reachable with a visible focus ring.
- Persist window and pane sizes; restore them on start, clamped to the current screens.
- Test every new shortcut with a widget test.
- Keep runner changes (entitlements, manifests) minimal and documented in the change.
