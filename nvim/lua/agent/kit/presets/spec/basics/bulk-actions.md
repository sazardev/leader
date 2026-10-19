<!-- name: Bulk actions -->
<!-- desc: acting on many items at once: selection, bulk edit, delete and export, progress, partial failure and undo -->
<!-- for: all -->
<!-- needs: lists -->
<!-- tech: jobs -->
<!-- design: data-tables toasts-feedback dialogs -->

## Requirements

### Selecting

The system must let a person choose many items and know how many are chosen.

- Given a list, when a person ticks items, then the number selected is shown and the bulk actions become available
- Given a filtered list, when the person selects all, then the selection says whether it covers the page or every match
- Given a selection, when the person changes page or filter, then the selection is kept or cleared as the interface says

### Acting

The system must apply one action to all the selected items and show how it goes.

- Given a selection, when the person chooses an action, then they see what will happen to how many items and must confirm if it destroys data
- Given a long action, when it runs, then progress is shown and the person can keep working or cancel
- Given items the person is not allowed to change, when the action runs, then those are skipped and reported

### Result and undo

The system must say what happened to every item and let the person take it back when possible.

- Given an action that finished, when some items failed, then a report lists which and why, and the rest are done
- Given a reversible action, when it finishes, then the person can undo it for a limited time

## Edge cases

- [Acting] An item in the selection was changed or deleted by someone else meanwhile: it is reported and the others continue
- [Acting] The same action is started twice on the same items: it is applied once
- [Selecting] A selection of thousands of items: it still works without freezing the screen
- [Result and undo] The person closes the page during a long action: it keeps running and its result can be found later

## Open questions

- [Selecting] Which is the largest selection that is allowed?
- [Acting] Which bulk actions exist, and which of them need a confirmation or a second person to approve?
- [Result and undo] For how long can an action be undone, and are deletions permanent?
