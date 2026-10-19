<!-- name: Toasts and feedback -->
<!-- desc: when to use toasts, banners and inline messages: duration, undo, stacking -->
<!-- for: all -->

## Components

- Pick by scope: inline message for one field or one block; toast for the result of an action the user just took; banner for a persistent state that affects the whole page or account (offline, expired plan, maintenance).
- GUI: toast: bottom-left (or bottom-center on mobile), 360 px max width, surface color with a status icon, one sentence plus at most one action ("Undo", "View"); never put a long explanation or a form inside.
- GUI: toast duration: 4 s for success, 8 s when it has an action, errors stay until dismissed; pause the timer on hover and focus; always include a close button.
- GUI: stack at most 3 toasts, newest at the bottom, 8 px gap; extra ones queue; identical messages merge into one with a count instead of repeating.
- GUI: undo over confirm for reversible actions: perform at once, toast "Moved to trash  Undo" for 8 s, then commit; keep the undo available if the user navigates within the app.
- GUI: banner: full width under the top bar, 48 px, status tint with icon, message, one action and a close button when dismissible; a blocking problem (offline, payment failed) is not dismissible and clears itself when resolved.
- GUI: inline success is a check and "Saved" text next to the control for 2 s; inline errors stay until fixed.
- GUI: write messages as result then next step: "Invoice sent to ana@example.com", "Could not save. Check your connection and try again."; no "Success!" alone.
- TUI: a single status line at the bottom: info in dim text for 4 s, errors in danger color until the next key press; critical failures print a full message above the prompt.

## Accessibility

- Toasts live in a `role="status"` region (`role="alert"` for errors) and must not steal focus; the action is reachable by keyboard; important messages are never toast-only.

## Rules for agents

- Never use a toast for something the user must act on before continuing.
- Never auto-dismiss an error or a message with a destructive consequence.
