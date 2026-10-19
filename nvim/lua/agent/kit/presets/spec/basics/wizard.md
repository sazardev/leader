<!-- name: Multi-step flows -->
<!-- desc: long tasks split into steps: back and next, validation per step, saved progress, summary and submit -->
<!-- for: all -->
<!-- tech: database -->
<!-- design: forms onboarding -->

## Requirements

### Steps

The system must guide a long task through steps with a clear sense of where the person is.

- Given a flow with steps, when it is shown, then the person sees the current step, how many there are and which are done
- Given a step, when the person goes back, then what they entered is still there
- Given a step that is not required, when the person skips it, then the flow goes on

### Validation

The system must catch mistakes where they are made.

- Given a step with invalid data, when the person goes next, then the problems are shown on that step and they do not advance
- Given steps that depend on earlier answers, when an earlier answer changes, then the later steps adapt and say what changed

### Progress and submit

The system must not lose the person's work and must let them check it before sending.

- Given a flow in progress, when the person leaves, then their progress is saved and they can resume where they left off
- Given all steps done, when the person reaches the end, then a summary of everything is shown with a way to edit each part
- Given a summary, when the person submits, then it is sent once and they see the result

## Edge cases

- [Progress and submit] The person double-clicks submit: it is sent once
- [Progress and submit] The person resumes after the rules of the flow changed: what is still valid is kept and the rest is asked again
- [Validation] The connection drops on the last step: the data is kept and the person can retry
- [Steps] The person uses the browser's back button: they go to the previous step, not out of the flow

## Open questions

- [Progress and submit] For how long is unfinished progress kept?
- [Steps] Must steps be done in order, or can the person jump to any of them?
- [Progress and submit] Can the flow be completed by someone other than who started it?
