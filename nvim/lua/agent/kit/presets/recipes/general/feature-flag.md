<!-- name: Feature behind a flag -->
<!-- desc: a feature behind a flag: default off, one place to read it, a removal plan and both branches tested -->
<!-- for: all -->
<!-- input: name | Name of the flag and feature (e.g. new checkout, dark mode) -->
<!-- input: does | What the feature does when it is on (one or two sentences) -->

# Recipe: the {{name}} flag

When on: {{does}}

## Make

- The flag `{{name_snake}}`, default off, declared in one flags module (or the project's config or flag service if it has one; otherwise a small typed module reading an environment variable or a settings file), with a comment stating the owner, the reason and the date it should be removed.
- One function (`is{{name_pascal}}Enabled` or the language's naming) that is the only place the flag is read; every branch calls it, nothing reads the raw value.
- The feature built behind it: the new path next to the old one, the old path unchanged while the flag is off. Anything that must be decided once (a user, a request) reads the flag once and passes the result down.
- If the project has users or tenants, the flag can be turned on for some of them (an allow-list or a percentage by a stable hash) and not only for everyone.
- A line in the docs or README listing the flag, how to turn it on and the checklist to remove it.

## Rules

- Off means identical behaviour to before the flag existed: no new queries, routes or UI visible, no migration that breaks the old path.
- A flag is temporary: no nested flags, no flag deciding another flag, and a plan to delete it (both the check and the dead branch).
- An unknown or unreadable value means off.
- Follow the existing config and naming style.

## Tests

- With the flag off the old behaviour is unchanged (the existing tests still pass untouched).
- With the flag on the new behaviour works as described above.
- The per-user or percentage rule, if present, is stable for the same user and an unset value is off.
