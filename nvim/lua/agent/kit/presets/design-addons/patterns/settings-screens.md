<!-- name: Settings screens -->
<!-- desc: grouping, instant vs saved changes, danger zone and search inside settings -->
<!-- for: all -->

## Components

- GUI: group settings into 4-7 sections by what the user is trying to do (Profile, Notifications, Security, Billing), not by technical area; the section list is a left column on wide screens and a list screen on narrow ones.
- GUI: each setting is a row: label (medium weight) and one line of helper text on the left, the control on the right; rows 56 px minimum, dividers between rows, section titles as small headings.
- GUI: toggles and selects apply instantly and confirm with a quiet "Saved" near the control; text inputs and anything with side effects use an explicit "Save" button with "Cancel", shown only when the form is dirty.
- GUI: never mix instant and saved controls inside one card; if a section must, label the saved part with its own button.
- GUI: show the effective value when a setting is inherited ("Using workspace default: English") with a "Reset to default" link per setting.
- GUI: settings search at the top of the screen filters rows by label and helper text, highlights matches, jumps to the section, and shows "No settings match "x"" when empty.
- GUI: danger zone is the last section, separated by a divider, titled "Danger zone", rows with danger-outlined buttons ("Delete workspace"); each action opens a confirmation that requires typing the resource name.
- TUI: a two-pane list: sections on the left, rows on the right as `label  value`; Enter edits, Space toggles, `/` searches, `r` resets the row to default; changes marked with `*` until saved with `w`.

## Accessibility

- Toggles are `role="switch"` with the label and state announced; sections are landmarks with headings; the search field is labelled and results count is announced.

## Rules for agents

- Every setting states its default and can be reset to it.
- Never apply a destructive or billing change instantly.
- Never hide a setting that is on by default from enterprise or admin users without saying who controls it.
