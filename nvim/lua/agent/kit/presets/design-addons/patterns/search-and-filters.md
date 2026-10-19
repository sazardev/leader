<!-- name: Search and filters -->
<!-- desc: search box, filter chips, applied filters bar, sorting, saved views and no-results -->
<!-- for: all -->

## Components

- GUI: search box 40 px with a leading search icon, placeholder naming what is searched ("Search invoices"), a clear button when it has text, and "/" as the focus shortcut; search runs as the user types after a 250 ms debounce, or on Enter for expensive queries.
- GUI: filters sit in a row above the results as chips (`Status: Open  v`); a chip opens a popover with the options and an "Apply" or instant behavior chosen per screen and kept consistent; more than 5 filters go behind a "Filters" button into a side panel.
- GUI: an applied-filters bar shows every active filter as a removable chip (x), the result count ("128 results"), and one "Clear all" link; the bar is absent when nothing is applied.
- GUI: sort is a separate dropdown labelled with the current choice ("Sort: Newest"); the default sort is named, and relevance is the default only when a query exists.
- GUI: search and filters live in the URL so a view can be shared, reloaded, and reached with Back; changing a filter resets pagination to page 1.
- GUI: saved views: "Save view" captures filters, sort and columns under a name; views appear as tabs or a menu, a modified view shows "Modified" with "Save" and "Reset".
- GUI: no results keeps the controls in place, echoes the query and active filters, and offers "Clear filters" (see empty states); a typo suggestion ("Did you mean ...") is shown when available.
- GUI: while loading, keep the previous results visible, dimmed, with a thin progress bar; never flash an empty list between queries.
- TUI: `/` opens an inline prompt, results filter live, `n/N` jump between matches, Esc clears the query; active filters are shown in the header line as `[status:open] [owner:me]` and `f` edits them.

## Accessibility

- Search is a `role="search"` landmark; announce the result count in a polite live region after each update; filter chips are buttons with names like "Remove filter Status: Open".

## Rules for agents

- Never reset the user's filters when they open and leave a detail view.
- Count and label every applied filter; an invisible filter is a bug.
