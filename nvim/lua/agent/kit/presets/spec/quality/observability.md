<!-- name: Observability and operations -->
<!-- desc: knowing what happens: logs, metrics, traces, error reports, alerts, operator audit and a status page -->
<!-- for: all -->
<!-- tech: analytics -->

## Requirements

### Logs and errors

The system must record what happens so a problem can be understood afterwards.

- Given any request or job, when it runs, then it leaves a log with an identifier that follows it through every part
- Given an error, when it happens, then it is reported with enough context to reproduce it and without personal data or secrets
- Given a person who reports a problem, when they give the identifier shown to them, then the team finds what happened

### Metrics and alerts

The system must show its health and warn the right people before users do.

- Given the service, when it runs, then it measures the load, errors and response times of its main actions
- Given a measure over its threshold (proposed below), when it stays there, then the people on call are alerted once with what is wrong
- Given an alert, when it is resolved, then it is closed and its cause is noted

### Operations and status

The system must make the work of the people who run it traceable, and keep users informed.

- Given an operator action on production data or settings, when it is done, then who did it, when and why is recorded
- Given an incident, when it affects people, then a public status page says what is affected and when it is solved

## Edge cases

- [Logs and errors] The same error happens thousands of times: it is grouped and counted, not sent as thousands of alerts
- [Logs and errors] A log line would include a password, token or card number: it is hidden before being stored
- [Metrics and alerts] The monitoring itself fails: someone is told that it is blind
- [Operations and status] An operator needs to see a person's data to solve a problem: the access is recorded and limited

## Open questions

- [Logs and errors] How long are logs kept, and which data must never appear in them?
- [Metrics and alerts] Which thresholds raise an alert (proposed: errors above 1% for 5 minutes), and who is on call?
- [Operations and status] Is there a public status page, and who writes its messages during an incident?
