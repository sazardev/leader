<!-- name: Loading, errors and feedback -->
<!-- desc: what the person sees while waiting, when something fails and after they act -->
<!-- for: all -->
<!-- design: toasts-feedback empty-states -->

## Requirements

### Waiting

The system must show that it is working whenever an action takes noticeable time.

- Given an action that takes more than a moment, when the person starts it, then they see progress and cannot trigger it twice by accident
- Given content that is loading, when the screen is shown, then it keeps its layout so nothing jumps when the content arrives

### Failures

The system must say what went wrong in the person's words and what they can do about it.

- Given a failed action, when it fails, then the message says what did not happen and offers to retry or to go on
- Given no connection, when the person acts, then they are told it is the connection and nothing they typed is lost

### Confirmation

The system must confirm what an action did and let the person undo what is easy to undo.

- Given a completed action, when it finishes, then the person sees what changed
- Given a destructive action, when the person confirms it, then they are told what will be lost, and an undo is offered where it is possible

## Edge cases

- [Waiting] The action succeeds after the person gave up waiting and left: the result is there when they return
- [Failures] The same failure happens many times in a row: the person sees one message, not a stack of them
- [Confirmation] A person undoes an action after someone else changed the same thing: the undo says it cannot apply

## Open questions

- [Waiting] What is the longest a person waits before the product says it is taking longer than usual?
- [Confirmation] Which actions can be undone, and for how long?
