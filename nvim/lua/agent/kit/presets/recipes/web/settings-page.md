<!-- name: Settings page -->
<!-- desc: a settings area with sections, instant vs saved changes, a danger zone and confirmations -->
<!-- for: ui -->
<!-- input: sections | The sections and what each controls (e.g. Profile: name and avatar; Notifications: email toggles; Danger zone: delete account) -->

# Recipe: settings with {{sections}}

## Make

- A settings area in the router the framework uses (`/settings`, or `/settings/<section>` per section), linked from the user menu or navigation, with a section list that shows where the user is and works on narrow screens.
- One component per section in the project's components folder, reading and writing through the project's data layer (query hook, loader and action, store).
- The way each setting is saved is decided by its kind: toggles and choices that are cheap and reversible save instantly with a quiet confirmation and an undo or retry on failure; text fields and anything with rules use a form with an explicit Save button, a disabled state while nothing changed, and a warning before leaving with unsaved changes.
- A danger zone at the end for destructive actions (delete account, reset data, revoke all sessions) visually separated, each behind a confirmation that names what will be lost; the most serious asks the user to type a word or password.
- Loading (skeleton of the section), error (what happened and a retry) and success states for every section.

## Rules

- The server validates and authorizes every change; the UI reflects what the server accepted, rolling back optimistic updates on failure.
- Settings take effect without a reload where it makes sense (theme, language); those that need a restart or sign in say so.
- Labels say what each option does, not how it is stored; destructive buttons use the project's danger style and are never the default focus.
- Accessible: grouped controls with legends, switches with labels and states, focus moved sensibly after a confirmation.
- Colors, spacing and type from DESIGN.md's tokens; follow the existing pages.

## Tests

- Each section loads and shows its current values; an instant toggle saves and rolls back when the request fails.
- A form section enables Save only after a change, saves, and warns on leaving with unsaved changes.
- The danger zone action does nothing until confirmed, and the typed confirmation must match.
