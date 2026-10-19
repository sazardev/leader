<!-- name: Version history -->
<!-- desc: the earlier states of what people edit: who changed what, compare, restore -->
<!-- for: all -->
<!-- tech: database -->
<!-- design: dialogs -->

## Requirements

### Keeping versions

The system must keep the earlier states of what people edit.

- Given an item that is edited, when the change is saved, then the previous state is kept with who changed it and when
- Given an item, when a person opens its history, then they see each version in order, newest first

### Comparing versions

The system must show what changed between two versions.

- Given two versions, when a person compares them, then the additions and removals are marked
- Given a version, when a person opens it, then they see it as it was, without changing the current one

### Restoring a version

The system must let a person go back to an earlier version without losing the ones after it.

- Given an earlier version, when a person restores it, then it becomes the current one
- Given a restore, when it happens, then the version it replaced stays in the history

## Edge cases

- [Keeping versions] Very frequent edits (typing) do not create a version each: they are grouped into one
- [Restoring a version] The item changed since the person opened the history: they are told before restoring over someone else's change
- [Comparing versions] A version made by an account that was deleted still shows who it was as a name, not as an error

## Open questions

- [Keeping versions] How many versions or how much time of history is kept?
- [Restoring a version] Can everyone restore, or only the owner and administrators?
- [Comparing versions] What is a version for this product: every save, or a point the person names?
