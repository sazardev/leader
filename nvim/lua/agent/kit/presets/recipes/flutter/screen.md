<!-- name: Flutter screen with its state -->
<!-- desc: a screen, its state (Riverpod Notifier or the Bloc/Cubit STACK.md names), its route and a widget test -->
<!-- for: flutter -->
<!-- input: name | Name of the screen (e.g. Profile, Order details) -->
<!-- input: shows | What it shows and what the user does there (one sentence) -->

# Recipe: the {{name_pascal}} screen

{{shows}}

## Make

- `{{name_pascal}}Screen`: the widget, in the feature folder STACK.md's layout uses (e.g. `lib/features/{{name_snake}}/presentation/{{name_snake}}_screen.dart`).
- Its state with the state management STACK.md names: Riverpod → a `{{name_pascal}}Notifier` (`Notifier`/`AsyncNotifier`, code generation when the project uses `riverpod_generator`) exposed as `{{name_camel}}Provider`; Bloc → a `{{name_pascal}}Cubit` with its state class. Loading, data, empty and error are explicit states.
- The route: registered where the project registers routes (`go_router`: a `GoRoute` with path `/{{name_kebab}}`), reachable from where the user would open it.
- The widget test: `test/features/{{name_snake}}/{{name_snake}}_screen_test.dart` (or where the existing tests live).

## Rules

- Widgets read state and send intents; no business rules in the widget: they live in the domain or the notifier.
- Every color, size and text style from the app's theme (DESIGN.md's tokens), never literals.
- Loading shows progress, an error shows what happened and a retry, an empty state says what to do next.
- Follow the existing screens: same folder shape, naming, imports and widget style.

## Tests

- The screen renders its data state (a fake or overridden provider/cubit, no network).
- The empty and error states render, and retry calls the state again.
- The main action the user takes there does what the sentence above says.
