<!-- name: Flutter data feature: model, repository, provider -->
<!-- desc: an immutable model, a repository interface + implementation, its provider and unit tests -->
<!-- for: flutter -->
<!-- input: name | Name of the entity (e.g. Note, Invoice) -->
<!-- input: source | Where the data comes from (REST endpoint, Supabase table, Firebase collection, local database) -->

# Recipe: {{name_pascal}} data

Data from: {{source}}.

## Make

- `{{name_pascal}}`: an immutable model (freezed + json_serializable when the project uses them, else `final` fields, `copyWith`, `==`/`hashCode` and `fromJson`/`toJson` by hand) in the domain or data folder STACK.md names.
- `{{name_pascal}}Repository`: the abstract interface the rest of the app depends on (list, get by id, create, update, delete: only those the source supports), returning domain types and typed failures, never raw JSON or exceptions from the client.
- Its implementation against {{source}}, using the client the project already has (Dio/http, Supabase, Firebase, drift…); mapping between DTO and model in one place.
- The provider (Riverpod) or the registration (get_it/Bloc) that gives the implementation to the app, overridable in tests.

## Rules

- The UI and notifiers see only the interface; the client stays inside the implementation.
- Errors become the project's failure type (or a sealed `{{name_pascal}}Failure`) with a message the UI can show.
- Generated files (`*.g.dart`, `*.freezed.dart`) are never written by hand: `build_runner` makes them.

## Tests

- The mapping: JSON → model → JSON round-trips, unknown or missing fields handled.
- The implementation with a faked client: success, empty, a server error and no connection each give the right result.
