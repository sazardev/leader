<!-- name: File upload -->
<!-- desc: drop zone, progress, previews, errors, limits and multiple files -->
<!-- for: all -->

## Components

- GUI: drop zone: dashed-outline area at least 160 px high with an icon, "Drag files here or Browse" where "Browse" is a button, and a line stating limits ("PNG, JPG or PDF, up to 10 MB each, max 5 files"); dragging over it changes to a primary tinted state with "Drop to upload".
- GUI: validate on selection before upload: type, size and count; rejected files are listed with the reason ("report.zip: file type not allowed") while valid ones continue; never silently drop a file.
- GUI: each file is a row: thumbnail (40 px for images, type icon otherwise), name truncated in the middle, size, a progress bar with percentage, and a cancel button; finished rows show a check and a remove button.
- GUI: upload in parallel (3 at a time), show overall progress when more than 3 files, and keep working if the user navigates inside the app (uploads continue in the background with a small indicator).
- GUI: errors are per file with a "Retry" action: network failure, too large, server rejected; resumable uploads resume instead of restarting; the form can be submitted only after required files finish, and says "Waiting for 2 uploads".
- GUI: single-file fields (avatar) show a preview in place with "Replace" and "Remove"; images support crop before upload when the aspect ratio matters.
- GUI: paste from clipboard and mobile camera capture work where relevant; accept uses `accept` plus server-side validation, never only the extension.
- GUI: removing an uploaded file is undoable until the form is saved; deleting one already saved asks for confirmation.
- TUI: `upload path/to/file` shows one line per file with a bar `file.zip  [#####-----] 52%  3.1 MB/s`; Ctrl+C cancels cleanly, a retry flag resumes; the final line prints the URL or id.

## Accessibility

- The drop zone is a real button or file input reachable by keyboard (Enter and Space open the picker); progress uses `role="progressbar"` with values; completion and errors are announced in a live region.

## Rules for agents

- Always show the limits before the user picks a file, not only after a failure.
- Never block the whole form on one failed file; the user can remove it and continue.
