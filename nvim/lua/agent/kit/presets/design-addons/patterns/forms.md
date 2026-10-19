<!-- name: Forms and validation -->
<!-- desc: labels, inline validation, error copy, submit states and autosave for every form -->
<!-- for: all -->

## Components

- GUI: label above the field, always visible (never placeholder-only); helper text below in muted text; field height 40 px, 16 px between fields, one column unless fields are short and related (city + postcode).
- GUI: mark the exception, not the rule: if most fields are required, label the optional ones "(optional)"; otherwise mark required ones with "*" plus a legend at the top.
- GUI: validate on blur, then on every change once a field has shown an error; never show an error while the user is still typing the first time. Clear the error the moment the value becomes valid.
- GUI: error text sits under the field in danger color with an icon, and says what to do: "Enter an email like name@example.com", not "Invalid input".
- GUI: submit button keeps its label and shows a spinner inside while sending, with the width fixed; it is disabled only while sending, never because the form is incomplete (explain the missing fields on submit instead).
- GUI: on submit with errors, focus the first invalid field and show a summary above the form linking to each error when there are 3 or more.
- GUI: autosave forms show "Saving..." then "Saved" in a small status line, never a toast per keystroke; debounce 800 ms and save on blur.
- TUI: one field per line as `Label  [value____]`, the focused field highlighted; Tab / Shift+Tab move between fields, Enter submits on the last field, Esc cancels with a confirmation if the form is dirty.
- TUI: errors appear on the line below the field in danger color, prefixed with `!`; the status line shows "N errors" while any remain.

## Accessibility

- Every input has a programmatically associated label; errors are linked with `aria-describedby` and announced with `aria-live="polite"`; invalid fields set `aria-invalid`.
- Use the right input `type` and `autocomplete` token so password managers and mobile keyboards work; never block paste.

## Rules for agents

- Never clear what the user typed after a failed submit or a server error.
- Never disable the submit button for validation; only for the in-flight request.
- Every form defines its empty, filled, error, sending and success states.
