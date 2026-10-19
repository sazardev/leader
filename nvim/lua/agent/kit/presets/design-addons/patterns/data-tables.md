<!-- name: Data tables -->
<!-- desc: columns, sorting, sticky header, row actions, selection, pagination and empty/loading/error rows -->
<!-- for: all -->

## Components

- GUI: header row sticky, 40 px; body rows 48 px (32 px in compact density); text columns left-aligned, numbers right-aligned in tabular figures, units in the header, not in every cell.
- GUI: the primary identifier column comes first and is sticky when the table scrolls horizontally; truncate long text with an ellipsis and the full value in a tooltip.
- GUI: sortable headers show an arrow for the active sort only; click cycles ascending, descending, none; the default sort is stated, never implicit. Sort is stable.
- GUI: row actions: one primary action is the row click; secondary actions in a trailing "more" menu (max 3 inline icons); destructive actions always inside the menu.
- GUI: selection with a leading checkbox column; selecting one or more rows replaces the header with a bulk bar ("3 selected" + actions + "Clear"); header checkbox selects the page, then offers "Select all N results".
- GUI: pagination for page-addressable data (25 rows default, 10/25/50/100), showing "1-25 of 1,204"; virtual scroll for feeds and logs over about 500 rows; keep scroll position when going back.
- GUI: loading shows skeleton rows with the same column widths; refreshing keeps old rows visible with a thin progress bar; error is a full-width row with the cause and a "Retry" button; empty is a row with a message and one action (see empty states).
- TUI: fixed header line in bold, columns separated by two spaces, the cursor row in the selection color, `j/k` or arrows move, Space toggles selection, `/` filters, `s` cycles sort on the current column, `g/G` first/last.
- TUI: a footer line shows position and totals: `12/1204  sorted by name asc  3 selected`.

## Accessibility

- Use real table semantics (`table`, `th scope`, `aria-sort`); a selected row is announced as selected; every row action has an accessible name including the row ("Delete invoice 1042").

## Rules for agents

- Never let columns shift width when data loads or sorts; set widths per column.
- Never put more than one destructive action per row in view; confirm bulk destructive actions with the count.
