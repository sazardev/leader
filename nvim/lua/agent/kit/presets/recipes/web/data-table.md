<!-- name: Data table -->
<!-- desc: a table with sorting, filtering, pagination, selection, bulk actions, states and accessible keyboard use -->
<!-- for: ui -->
<!-- input: name | Name of the table (e.g. Orders, Team members) -->
<!-- input: columns | Its columns and what each shows (e.g. order number, customer, total, status, date) -->

# Recipe: the {{name_pascal}} table

Columns: {{columns}}.

## Make

- A `{{name_pascal}}Table` in the framework STACK.md names, built on the table helper the project already uses (TanStack Table, the UI kit's table) or plain semantic markup, in the components folder of its layout, typed rows and columns.
- Sorting (click a header: ascending, descending, none, with the current sort in the header), filtering by text and by the columns where it makes sense, and pagination with a page size choice and the total; the state lives in the URL so a link reproduces the view.
- Server-side sorting, filtering and pagination when the data comes from the project's API and can be large; client-side otherwise.
- Row selection (one, page, none) with a count, and bulk actions that appear for a selection; destructive ones ask for confirmation.
- Loading (skeleton rows with the same shape), empty (says why and what to do, differing between "no data" and "no match for the filters" with a clear-filters button), and error (what happened and a retry).

## Rules

- Real `table`, `th scope`, `tr`, `td` semantics (or the grid roles when it is interactive); sortable headers are buttons with `aria-sort`; selection checkboxes are labeled by their row.
- Fully usable with the keyboard, focus visible, loading and result counts announced to screen readers (a polite live region).
- Long text truncates with its full value available; numbers aligned right in a tabular font; on narrow screens the table scrolls or becomes cards, never overflows the page.
- Colors, spacing and type from DESIGN.md's tokens.
- Follow the existing components: file shape, props, naming.

## Tests

- Renders rows from data; sorting by a column changes the order; a filter narrows the rows; the page changes.
- Selecting rows shows the bulk actions with the right count; a destructive action asks first.
- The loading, empty (both kinds) and error states render; the retry calls the loader again.
