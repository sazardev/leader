<!-- name: Validated form -->
<!-- desc: a form with schema validation shared with the server, inline errors, submit states and accessibility -->
<!-- for: ui -->
<!-- input: name | Name of the form (e.g. Contact, Edit profile) -->
<!-- input: fields | Its fields with types and rules (e.g. email: required, valid; message: required, 10-500 chars) -->

# Recipe: the {{name_pascal}} form

Fields: {{fields}}.

## Make

- A `{{name_pascal}}Form` in the framework STACK.md names, in the components folder of its layout, using the form library the project already uses (React Hook Form, TanStack Form, Formik, Superforms, VeeValidate, native) or none if there is none.
- One schema `{{name_camel}}Schema` with the project's validation library (Zod, Valibot, Yup…) holding the rules for {{fields}}; the same schema imported by the server handler when client and server share a language, otherwise the same rules written once on each side and tested against the same cases.
- Inline errors beside each field, shown after the field is touched or the form is submitted, plus a summary at the top that moves focus to the first error on a failed submit.
- Submit states: idle, submitting (button disabled with progress, no double submit), success (message and what happens next, form reset or navigation), failure (the server's field errors mapped onto the fields, and a general message for network or server errors that keeps what was typed).
- Sensible input types, `autocomplete` values, and the right mobile keyboard.

## Rules

- Every input has a visible label tied by `for`/`id`; errors are linked with `aria-describedby` and invalid fields carry `aria-invalid`; required is marked in text as well as in color.
- The server validates again and never trusts the client; errors never expose internals.
- Do not clear the form on an error; trim text where it makes sense, never silently change what the user typed otherwise.
- Colors, spacing and type from DESIGN.md's tokens; follow the existing forms.

## Tests

- The schema accepts valid input and rejects each invalid case with the right message.
- The form shows inline errors on a bad submit, calls the submit handler once with valid data, and shows the submitting state.
- A server error appears on its field, a network error keeps the values; labels and errors are reachable by accessible name.
