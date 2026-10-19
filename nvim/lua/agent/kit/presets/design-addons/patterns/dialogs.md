<!-- name: Dialogs and overlays -->
<!-- desc: modal vs drawer vs popover, focus trap, destructive confirmation copy, close behavior -->
<!-- for: all -->

## Components

- GUI: choose the lightest overlay: popover for a small tooltip-like choice anchored to a control; drawer (right side, 420-560 px) for viewing or editing an object while keeping context; modal dialog (max 480 px, 640 px for forms) only for a decision or short task that must be finished before continuing; a full page for anything longer.
- GUI: modal structure: title (verb or question), body, footer with buttons right-aligned, primary on the right, secondary "Cancel" to its left; a close "x" at the top right; scrim at 50% over the page; max one dialog open at a time, never a dialog opening a dialog.
- GUI: open with focus on the first field, or on the least destructive button for confirmations; trap focus inside; on close return focus to the control that opened it; background is inert and does not scroll.
- GUI: close with Esc, the x button, and clicking the scrim, except when the dialog holds unsaved input: then ask "Discard changes?" with "Keep editing" as the default.
- GUI: destructive confirmation copy: title "Delete 'Project Apollo'?", body states the consequence and whether it can be undone ("This removes 14 files and cannot be undone."), buttons name the action ("Delete project" in danger color) and "Cancel"; never "OK / Yes / No".
- GUI: for irreversible high-impact actions require typing the resource name before the danger button enables.
- GUI: on mobile, dialogs become bottom sheets with a drag handle, up to 90% height, scrollable body with a fixed footer.
- TUI: a centered box with a title in the border, the same footer keys shown inside (`[Enter] Delete  [Esc] Cancel`), default on Cancel for destructive prompts; `y/n` accepted for simple confirmations.

## Accessibility

- Use `role="dialog"` (`alertdialog` for destructive confirmations) with `aria-modal`, `aria-labelledby` pointing to the title and `aria-describedby` to the body.

## Rules for agents

- Never open a modal on page load or without a user action, except a blocking session or consent prompt.
- Button labels are verbs naming the result; the destructive one is never the default focus.
