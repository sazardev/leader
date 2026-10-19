<!-- name: Lists, search and deleting -->
<!-- desc: pagination, empty states, search, sorting and filters, delete with undo and a trash -->
<!-- for: all -->
<!-- tech: database search -->
<!-- design: data-tables search-and-filters empty-states -->

## Requirements

### Browsing a list

The system must show long lists a page at a time, with an empty state that says what to do.

- Given more items than fit on a page, when the list opens, then the first page shows and more load on demand (next page or scrolling)
- Given no items yet, when the list opens, then it says so and offers the action that creates the first one
- Given a list that fails to load, when it opens, then it shows the error and a way to retry

### Search and filters

The system must let a person find items by text, filter them and sort them.

- Given a search text, when they type it, then the list shows only matching items, case and accents ignored, after a short pause
- Given a filter or a sort order, when they choose it, then the list updates and keeps it while they stay on the list
- Given a search with no results, when it runs, then it says nothing matched and offers to clear the search and filters

### Deleting

The system must let a person delete items and undo the deletion.

- Given an item, when they delete it, then it disappears from the list and an undo is offered for a few seconds
- Given a deleted item, when they undo, then it comes back exactly as it was, in the same place
- Given deleted items, when they open the trash, then they can restore them or delete them for good until the trash empties itself

## Edge cases

- [Browsing a list] Items added or deleted while paging: no item is shown twice or skipped
- [Search and filters] A search typed fast: only the results of the last text are shown
- [Deleting] Several items deleted at once: one undo restores all of them

## Open questions

- [Browsing a list] Pages with numbers, a "load more" button, or infinite scrolling? How many items per page?
- [Deleting] How long do items stay in the trash before they are deleted for good?
- [Search and filters] Which fields are searched, and which filters and sort orders are offered?
