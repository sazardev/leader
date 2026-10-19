<!-- name: CRUD resource -->
<!-- desc: a full resource: model, validation, migration, list/create/update/delete, authorization and tests -->
<!-- for: server ui -->
<!-- input: name | Name of the resource (e.g. Invoice, Project) -->
<!-- input: fields | Its fields with types and rules (e.g. title: text, required, max 120; due date: optional date) -->

# Recipe: the {{name}} resource

Fields: {{fields}}.

## Make

- The model `{{name_pascal}}` and its validation (required, formats, limits, uniqueness) with the project's schema or ORM tools, in the folder STACK.md's layout uses for domain code.
- Persistence through the project's data layer: a migration for `{{name_snake}}` (primary key, timestamps, indexes for what the list filters and sorts by), and one repository or query module.
- Operations: list, get one, create, update, delete, on the project's API (routes, server actions, RPC, controllers) and, where the project has a UI, the screens or components for list, detail and form.
- The list takes pagination (a limit with a maximum), a sort among a fixed set of fields and the filters the fields imply; it answers the total or a next-page cursor.
- Authorization: who may read, change and delete a {{name}}, checked on the server for every operation; a user never reaches another owner's rows.

## Rules

- Validate at the edge and again in the model; never trust the client's id, owner or timestamps.
- Errors map in one place: invalid input 400/422 with the field, not found 404, forbidden 403, conflict 409, anything else 500 without internals.
- Delete says whether it is soft (a deleted flag) or hard, following what the project already does; confirm before it in the UI.
- The UI shows loading, empty, error and a success message after each write.
- Follow the existing resources: file shape, naming, response format.

## Tests

- Validation: each rule accepts a valid value and rejects an invalid one.
- Each operation: happy path, not found, invalid input, and a user without permission.
- The list: first page, last page, a sort, a filter and an empty result.
