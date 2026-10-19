<!-- name: Reliability and recovery -->
<!-- desc: staying up and not losing data: availability, backups and restore, degradation, retries and disaster recovery -->
<!-- for: all -->
<!-- tech: database jobs -->

## Requirements

### Availability

The system must be there when people need it.

- Given the service, when it runs, then it is available as much as the target below (proposed: 99.9% a month)
- Given a planned maintenance, when it will affect people, then they are told in advance and it happens at the quietest hour
- Given a part that fails (a payment provider, an email service), when the rest still works, then the person can keep doing everything that does not need it and is told what is down

### Data safety

The system must not lose what people entrusted to it.

- Given the data, when time passes, then it is backed up as often as the target below (proposed: every day, kept for 30 days)
- Given a backup, when it is tested, then the test shows that it can be restored
- Given an action that changes data, when it fails midway, then nothing is left half done

### Recovery

The system must come back quickly and in a known state after a serious failure.

- Given a total failure, when recovery starts, then the service returns within the time target below and loses at most the data target below (proposed: 4 hours, 24 hours of data)
- Given a mistaken deletion, when it is noticed, then the data can be recovered as long as the retention below allows

## Edge cases

- [Data safety] A backup is taken while people write: it is consistent and not corrupt
- [Availability] A failing external service is retried: retries wait longer each time and never repeat a charge or an email
- [Recovery] The restore is done on another environment: what it needs (secrets, files, settings) is known beforehand
- [Data safety] The disk or the quota is full: writes are refused with a clear message instead of corrupting data

## Open questions

- [Availability] What availability and recovery times does the business need, and what does an hour of downtime cost?
- [Data safety] How long must backups be kept, and where, including what the law requires?
- [Recovery] Who is called when it fails outside working hours, and who decides to go on with a recovery?
