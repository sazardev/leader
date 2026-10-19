<!-- name: Paginated list and detail -->
<!-- desc: a paginated list screen and its detail screen, states, pull to refresh, navigation, repository and tests -->
<!-- for: flutter -->
<!-- input: name | Name of the thing listed (e.g. Order, Contact) -->
<!-- input: shows | What the list row shows and what the detail adds (one or two sentences) -->

# Recipe: {{name_pascal}} list and detail

{{shows}}

## Make

- `{{name_pascal}}ListScreen` and `{{name_pascal}}DetailScreen` in the feature folder STACK.md's layout uses (e.g. `lib/features/{{name_snake}}/presentation/`), with a `{{name_pascal}}` model in the domain layer.
- A `{{name_pascal}}Repository` (abstract in the domain, one implementation in data) with `fetchPage(cursor or page, size)` and `fetch(id)`, using the project's HTTP client and its error mapping; typed failures, not raw exceptions.
- State with the management STACK.md names: Riverpod, a list notifier (`AsyncNotifier`) that holds items, the next page, `isLoadingMore` and `hasMore`, plus a detail provider by id; Bloc, a `{{name_pascal}}ListCubit` and detail cubit. Loading, data, empty and error are explicit states.
- The list: `ListView.builder` loading the next page near the end, a pull-to-refresh (`RefreshIndicator`) that reloads the first page, a footer with progress or a retry when a later page fails (earlier items stay visible).
- Routes where the project registers them (`go_router`: `/{{name_kebab}}` and `/{{name_kebab}}/:id`); tapping a row opens the detail, which loads by id when opened from a link and shows what the list already knows while it loads.
- Tests in `test/features/{{name_snake}}/` (or where the existing ones live).

## Rules

- Widgets read state and send intents; no paging logic or HTTP in a widget.
- Pages never duplicate items, a refresh does not run twice at once, and leaving the screen cancels or ignores late responses.
- Every color, size and text style from the app's theme (DESIGN.md's tokens); rows have large enough tap targets and semantics labels.
- Loading shows progress, errors show what happened and a retry, empty says what to do next.
- Follow the existing screens: folder shape, naming, imports, widget style.

## Tests

- Repository: a page maps to models; an error maps to a typed failure (a fake HTTP client).
- The list state: first page, next page appended, last page stops loading, refresh replaces, failure keeps items.
- Widget tests with overridden providers or cubits: list data, empty and error with retry; tapping a row navigates to the detail, which renders its data, loading and not-found.
