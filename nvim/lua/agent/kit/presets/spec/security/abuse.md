<!-- name: Limits and abuse protection -->
<!-- desc: rate limits, bots, locking attempts, reporting and blocking -->
<!-- for: all -->
<!-- tech: auth -->
<!-- design: auth-screens -->

## Requirements

### Rate limits

The system must stop anyone from using more than their fair share.

- Given a person or client over the limit, when they ask again, then they are refused with how long to wait
- Given an ordinary person, when they use the product normally, then they never meet a limit

### Protecting sign-in and forms

The system must slow down guessing and automated use of forms.

- Given repeated failed sign-ins, when they pass the allowed number, then more tries are delayed and the account owner is told
- Given a form open to everyone, when it is used by automated means, then it is challenged without blocking real people

### Reporting and blocking

The system must let people report what is abusive and let the team act on it.

- Given content or a person, when someone reports it, then the team sees the report with its context
- Given an abusive account, when the team blocks it, then it cannot sign in and its reason is recorded

## Edge cases

- [Protecting sign-in and forms] An attacker locking someone else's account by failing on purpose: the lock slows tries, it does not block the real owner
- [Rate limits] People behind one shared address (an office) are not limited as one person
- [Reporting and blocking] A blocked person asks why: they get the reason and a way to appeal

## Open questions

- [Rate limits] Which limits per person, per address and per API key?
- [Reporting and blocking] Who reviews reports and in how much time?
