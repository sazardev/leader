<!-- name: Performance -->
<!-- desc: speed people can feel: response and load times, perceived speed, size limits and caching -->
<!-- for: all -->
<!-- tech: database search -->
<!-- design: data-tables empty-states -->

## Requirements

### Response time

The system must answer fast enough that people do not wait to do their work.

- Given a common action, when a person does it, then the result shows within the target below (proposed: 1 second for 95% of requests)
- Given a screen with data, when it opens, then its main content shows within the target below (proposed: 2.5 seconds on an average connection)
- Given an action that takes longer, when it runs, then the person sees progress and can do something else

### Perceived speed

The system must feel fast even when work takes time.

- Given a screen that loads data, when it waits, then it shows the layout of what is coming instead of a blank page
- Given a change the person makes, when it is likely to succeed, then it shows at once and is corrected if the server refuses it

### Size and load

The system must stay fast as data and people grow.

- Given a very long list, when it is shown, then it loads in parts and stays fast to scroll
- Given many people using it at once, when the load grows up to the target below (proposed: ten times today's), then response times stay within their targets
- Given a request for too much data, when it is made, then it is limited or paged and says so

## Edge cases

- [Response time] A slow connection or an old device: the main task still works, only slower
- [Size and load] One account has a hundred times more data than the average: it does not slow down the others
- [Perceived speed] A fast change is shown and then refused by the server: the person is told and the screen returns to the real state
- [Response time] A request takes too long: it ends with an error the person can retry, not with an endless wait

## Open questions

- [Response time] Which actions are the most important and which time is acceptable for each?
- [Size and load] How many people, records and requests per day must it handle at launch and in a year?
- [Response time] Which devices and connections must it work well on?
