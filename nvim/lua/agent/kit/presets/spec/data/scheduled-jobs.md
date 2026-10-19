<!-- name: Background and scheduled jobs -->
<!-- desc: work that runs later or on a schedule: retries, status, failures people can see -->
<!-- for: all -->
<!-- tech: jobs -->

## Requirements

### Running in the background

The system must do slow work out of the person's way and tell them how it goes.

- Given a slow action, when a person starts it, then it runs in the background and they see its state
- Given a finished job, when it ends, then the person is told with its result

### Schedules

The system must run recurring work on time and never twice for the same moment.

- Given a schedule, when its time comes, then the job runs once
- Given a job that failed, when it is retried, then it does not repeat what already succeeded

## Edge cases

- [Running in the background] The system restarts in the middle of a job: it continues or starts over without duplicating its effects
- [Schedules] The server was off at the scheduled time: the job runs when it is back, once, or is skipped as decided below

## Open questions

- [Schedules] Which jobs are recurring and at what time zone?
- [Running in the background] How many retries, and who is told when all of them fail?
