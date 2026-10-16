<!-- name: Flutter offline-first -->
<!-- desc: drift (SQLite) as the source of truth, outbox sync with a conflict policy, background sync, Riverpod -->

# STACK.md: Flutter offline-first

## Summary

A Flutter app that works without a network: the local SQLite database (drift) is the source of truth for the UI, every
write goes to the database and to an **outbox** in one transaction, and a sync engine pushes the outbox and pulls
changes when the device is online (foreground and background). Conflicts are resolved by an explicit, documented policy.
The UI never waits on the network: it watches database queries and shows each record's sync status.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Dart 3.5+ | Sealed classes and patterns for sync states |
| Framework | Flutter (stable channel) | One codebase for Android and iOS |
| Local database | `drift` (SQLite) + `drift_flutter` | Typed queries, reactive `watch()` streams, migrations |
| Sync | Own sync engine: outbox table + pull by cursor (`updated_at`/version) | Predictable, testable, no vendor lock-in |
| Background work | `workmanager` (Android WorkManager / iOS BGTaskScheduler) | Sync when the app is closed, OS-scheduled |
| Connectivity | `connectivity_plus` (a hint) + real request outcome (the truth) | "Connected" does not mean "reachable" |
| HTTP | `dio` with timeouts and retry interceptor | Cancellation, backoff |
| IDs | Client-generated UUID v7 (`uuid`) | Records exist before the server knows them; time-ordered |
| State | `flutter_riverpod` + `riverpod_generator` | StreamProviders over drift queries |
| Models | `freezed` + `json_serializable` | Immutable entities and sync DTOs |
| Lint | `very_good_analysis` | Strict analysis |
| Testing | `flutter_test`, drift in-memory database, `mocktail`, `fake_async` | Sync tested deterministically |
| Deploy | Store builds per flavor | See the deploy add-on for the pipeline |

## Project layout

```
lib/
  main.dart                                 opens the database, registers background sync, ProviderScope
  app/                                      app.dart, router.dart, theme/
  core/
    db/
      app_database.dart                     @DriftDatabase: tables + DAOs + migration strategy
      migrations/                           one step per schema version (from1To2.dart…)
      tables/outbox_table.dart              id, entity, entity_id, operation, payload, attempts, last_error, created_at
      tables/sync_state_table.dart          per-entity pull cursor
    sync/
      sync_engine.dart                      push outbox → pull changes → apply; one run at a time (lock)
      push_outbox.dart                      sends pending operations in order, marks done/failed
      pull_changes.dart                     fetches since cursor, applies in one transaction
      conflict_policy.dart                  the rule (e.g. server wins for fields X, last-write-wins for Y)
      background_sync.dart                  workmanager callback → SyncEngine.run()
      sync_status.dart                      sealed: synced | pending | failed(error)
    network/api_client.dart                 dio + interceptors
  features/
    visits/
      domain/visit.dart                     entity with syncStatus
      domain/visits_repository.dart         interface: watchAll(), save(), delete()
      data/visits_table.dart                drift table (id UUID, fields, updated_at, deleted flag)
      data/visits_dao.dart                  queries + watch streams
      data/local_visits_repository.dart     writes row + outbox entry in ONE transaction
      data/visit_sync_adapter.dart          entity ↔ API payload, apply remote change
      presentation/visits_controller.dart
      presentation/visits_page.dart         shows per-row sync badge
test/
```

Dependency direction: `presentation → domain ← data`; `core/sync` depends on per-feature sync adapters through an
interface, never on presentation. The UI reads ONLY the local database; only `core/sync` talks to the API.

## Conventions

- Every write = local row change + outbox entry in one drift transaction; nothing writes to the API directly from a feature.
- Deletes are soft (`deleted` flag) until the server confirms; then the row is purged.
- Every synced table has `id` (client UUID v7), `updated_at` (server time when known) and `version` or equivalent for conflict detection.
- The conflict policy is written in `conflict_policy.dart` and in this file; changing it is a reviewed decision.
- Push is idempotent: the server accepts the same operation id twice without duplicating effects.
- Retries use exponential backoff with jitter; after N failures the item is `failed` and visible to the user, never silently dropped.
- Schema changes bump `schemaVersion` with a migration step and a migration test.

## Commands

| Task | Command |
| --- | --- |
| Install | `flutter pub get` |
| Generate | `dart run build_runner build --delete-conflicting-outputs` |
| Dump schema | `dart run drift_dev make-migrations` |
| Run | `flutter run` |
| Test | `flutter test` |
| Lint | `flutter analyze` |
| Format | `dart format .` |

## Testing

- Repositories against an in-memory drift database (`NativeDatabase.memory()`): a save creates the row AND the outbox entry.
- Sync engine with a fake API: push order, idempotent retries, backoff (`fake_async`), partial failure, conflict cases from `conflict_policy.dart`.
- Migration tests for every schema version (drift's generated schema verifier).
- A "kill mid-sync" test: interrupting between push and pull leaves the database consistent.
- Widget tests show the right sync badge for synced, pending and failed rows.

## Quality gates

- `flutter analyze` zero issues; `dart format --set-exit-if-changed .`.
- `flutter test` passes, including migration and sync tests; generated code and drift schema dumps are up to date.

## Dependencies

- Allowed: the table above. A sync framework (PowerSync, Brick, ElectricSQL) only by an explicit decision that replaces `core/sync`.
- Do NOT use: `shared_preferences` or files as a data store, `hive`/`isar` next to drift, direct API calls from features, server-generated IDs for records created offline.

## Rules for agents

- Never call the API from a feature or a widget: write to the local database; `core/sync` does the rest.
- Every local write and its outbox entry happen in the same transaction.
- Never block the UI on the network; screens watch drift queries.
- Never change a synced table without a migration step and its test.
- Every new synced entity gets a sync adapter, a conflict rule and tests for push, pull and conflict.
- Sync runs are serialized (one at a time) and safe to interrupt at any point.
- Show sync status per record; failed items offer retry, they are never discarded silently.
- Use client-generated UUID v7 for new records; never auto-increment IDs for synced tables.
