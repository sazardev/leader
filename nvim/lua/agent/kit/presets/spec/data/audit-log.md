<!-- name: Audit log -->
<!-- desc: who changed what and when, read-only history, what is never logged, retention -->
<!-- for: all -->
<!-- needs: accounts -->

## Requirements

### Recording changes

The system must record every change to important data: who did it, when, and what changed.

- Given a change to a recorded kind of data, when it is saved, then an entry keeps the person, the time, the action and the values before and after
- Given an action refused for lack of permission, when it is attempted, then it is recorded as refused
- Given any entry, when anyone tries to edit or delete it, then it is refused: the log is append-only

### Reading the log

The system must let the people allowed to do so read the history.

- Given the log screen, when it opens, then it lists entries newest first with who, what and when
- Given filters by person, kind of data, action and dates, when they are applied, then only matching entries show
- Given an item, when its history is opened, then it shows every entry about that item

## Edge cases

- [Recording changes] Secrets (passwords, tokens, card numbers) are never written to the log, not even masked parts that can be joined
- [Recording changes] A change made by the system itself (a scheduled job) names the job instead of a person
- [Reading the log] A deleted person still appears by name in old entries

## Open questions

- [Recording changes] Which kinds of data and actions are recorded?
- [Reading the log] Who can read the log?
- [Recording changes] How long are entries kept?
