<!-- name: Offline and sync -->
<!-- desc: work without a connection: local copy, queued changes, sync, conflicts, what the user sees -->
<!-- for: all -->
<!-- tech: database -->
<!-- design: toasts-feedback -->

## Requirements

### Working offline

The system must keep working without a connection on what the person already has on the device.

- Given no connection, when the person opens the app, then they see their data as it was last synced and that they are offline
- Given no connection, when they create or change something, then it is saved on the device and marked as not synced yet
- Given an action that needs the server (a payment, an invitation), when they try it offline, then it says it needs a connection

### Syncing

The system must send the changes made offline when the connection comes back, and bring the newer data.

- Given changes waiting, when the connection returns, then they are sent in the order they were made and marked synced
- Given newer data on the server, when the device syncs, then the local copy is updated without losing local changes
- Given a change the server refuses, when it syncs, then the person is told which change and why, and can fix or discard it

### Conflicts

The system must resolve a change made in two places at once in a way the person understands.

- Given the same item changed on two devices, when both sync, then the rule decided below applies and nobody's change disappears silently
- Given a conflict that needs a person, when it happens, then they see both versions and choose

## Edge cases

- [Syncing] The app is closed before the changes are sent: they are sent the next time it opens
- [Conflicts] An item deleted on one device and changed on another
- [Working offline] The device runs out of space for the local copy

## Open questions

- [Conflicts] Which rule wins a conflict: the last change, the server, or always ask?
- [Working offline] Which data is kept on the device, and for how long?
