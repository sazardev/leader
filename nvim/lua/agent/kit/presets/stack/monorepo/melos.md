<!-- name: Dart / Flutter monorepo (Melos) -->
<!-- desc: Flutter monorepo: pub workspaces + Melos, apps/ and packages/ (core, ui kit, features), versioning -->

# STACK.md: Dart / Flutter monorepo (Melos)

## Summary

Several Flutter apps and Dart packages in one repository. Dart pub workspaces (Dart 3.6+) give one resolution and one
lockfile; Melos runs scripts across packages, filters by changed packages and handles versioning/changelogs. Features are
packages, so their boundaries are enforced by `pubspec.yaml` dependencies, and apps only compose them.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Dart 3.6+ / Flutter stable | Pub workspaces support |
| Workspace | pub workspaces (`workspace:` in root pubspec, `resolution: workspace` in members) | One `pub get`, shared lockfile |
| Orchestration | Melos 7 (`melos:` section in the root pubspec) | Scripts, filters, versioning |
| State / DI | Riverpod (generator) | Shared across apps |
| Navigation | go_router | Per app |
| Models | freezed + json_serializable | Immutable shared models |
| UI kit | `packages/ui_kit` (theme, tokens, components, goldens) | One design system |
| Lint | `very_good_analysis` from a shared `analysis_options.yaml` | One rule set |
| Testing | flutter_test, mocktail, golden tests | Per package |
| Versioning | `melos version` with Conventional Commits | Changelogs per package |
| CI | GitHub Actions running `melos run ... --diff=origin/main` | Only changed packages |

## Project layout

```
pubspec.yaml                    workspace: [apps/*, packages/**]; melos: scripts
analysis_options.yaml           shared lints (included by every package)
apps/
  customer_app/                 composes features; routes, flavors, main_*.dart
  admin_app/
packages/
  core/
    core_domain/                pure Dart: entities, value objects, failures
    core_network/               dio client, interceptors
    core_storage/
  ui_kit/                       theme, tokens, widgets (one per file), goldens
  features/
    orders/                     lib/src/{domain,data,presentation}, lib/orders.dart = public API
    auth/
tools/                          scripts used by melos (codegen checks, coverage merge)
```

Dependency direction: `apps → features → core, ui_kit`; `core_domain → nothing`. Features never depend on each other; shared needs move to `core`. Each package exports only through `lib/<package>.dart`; nothing imports `package:x/src/...` from outside the package.

## Conventions

- Package names in `snake_case`, prefixed by area (`core_`, `feature_` optional); `publish_to: none` for internal packages.
- Every member pubspec has `resolution: workspace`; dependency versions are aligned across packages.
- Every package has the same scripts surface (analyze, test, build_runner) so Melos can run them everywhere.
- One file = one class/widget/provider; `lib/src/` is private, the barrel file is the public API.
- Features expose their routes and providers through their public API; apps register them.
- New feature = `packages/features/<name>` (copied from the template), added to the workspace, wired in the app.

## Commands

| Task | Command |
| --- | --- |
| Install | `dart pub get` (root, resolves the whole workspace) |
| Bootstrap | `melos bootstrap` |
| Analyze | `melos run analyze` (`dart analyze --fatal-infos` in each package) |
| Test | `melos run test` |
| Changed only | `melos run test --diff=origin/main` |
| Generate | `melos run build_runner` |
| Format | `dart format .` |
| Run app | `cd apps/customer_app && flutter run --flavor dev -t lib/main_dev.dart` |
| Version | `melos version` |
| Outdated | `dart pub outdated` |

## Testing

- Each package has its own `test/`; domain and data layers fully unit tested with mocktail fakes.
- `ui_kit` has golden tests for every component (light/dark, text scale).
- Features test controllers with Riverpod overrides and widgets inside `ProviderScope`.
- Apps hold integration tests (`integration_test/`) for their critical flows only.
- CI tests only changed packages and their dependents.

## Quality gates

- `melos run analyze` with zero infos/warnings; `dart format --set-exit-if-changed .`.
- `melos run test` passes; goldens unchanged unless updated on purpose.
- Generated files committed and up to date (CI runs build_runner and diffs).
- No dependency between two feature packages; no `src/` imports across packages (lint `implementation_imports`).

## Dependencies

- Third-party packages added to the package that uses them, same version range everywhere.
- Do NOT use: path dependencies outside the workspace, `dependency_overrides` committed, feature-to-feature imports, GetX, separate lockfiles per package.

## Rules for agents

- Add a new package to the root `workspace:` list and give it `resolution: workspace`.
- Never import `package:<other>/src/...`; use the package's public library.
- Put shared code in `core_*` or `ui_kit`, never by making one feature depend on another.
- Run Melos scripts with `--diff` or a scope to verify only what changed, then the affected apps.
- Never edit generated files; run `melos run build_runner`.
- Colors, text styles and spacing come from `ui_kit` tokens.
- Commit messages follow Conventional Commits with the package as scope (`feat(orders): …`): `melos version` depends on it.
- Keep apps thin: routes, flavors and wiring only.
