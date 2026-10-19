<!-- name: Flutter form with validation -->
<!-- desc: a form screen: fields, validation, submit with loading and error, and its widget test -->
<!-- for: flutter -->
<!-- input: name | Name of the form (e.g. Sign up, New invoice) -->
<!-- input: fields | Its fields and their rules (e.g. email required valid; password 8+ chars) -->

# Recipe: the {{name}} form

Fields and rules: {{fields}}.

## Make

- `{{name_pascal}}FormScreen` with a `Form` and one field per item above, labels and hints in the app's language, the right keyboard type and autofill hints per field.
- Validators as pure functions (a `{{name_snake}}_validators.dart` next to it or the project's validators file): one per rule, returning the message to show.
- Submit through the state management STACK.md names: a notifier/cubit method that validates, sends and exposes idle/submitting/success/failure.
- The route to the screen, where the project registers routes.

## Rules

- Submit is disabled while submitting; a second tap never sends twice.
- Errors from the server show next to the field they concern, or above the button when they concern the form.
- Focus moves to the next field on the keyboard's next action; the last one submits.
- Theme tokens from DESIGN.md for every color and spacing.

## Tests

- Each validator: valid, empty, and each rule broken.
- The widget: submit with invalid fields shows the messages and sends nothing; with valid fields it sends once and shows success; a failure shows its message.
