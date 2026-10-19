<!-- name: Public API and webhooks -->
<!-- desc: letting other software read and act: keys, limits, versions, events sent out -->
<!-- for: all -->
<!-- needs: accounts -->
<!-- tech: auth database -->

## Requirements

### API access

The system must let other software use the product's data and actions on behalf of an account.

- Given an account, when it creates an API key, then it is shown once and can be revoked
- Given a request with a valid key, when it asks for something the account may do, then it gets it; otherwise it gets a clear error

### Webhooks

The system must tell other software when something happens.

- Given a webhook address, when an event happens, then the system sends it signed so the receiver can trust it
- Given a receiver that fails, when the delivery fails, then it is retried and the failures can be seen by the owner

### Versions and limits

The system must keep the API stable and fair.

- Given a client of one version, when the API changes, then that client keeps working until the end of its notice period
- Given a client over its limit, when it asks again, then it receives how long to wait

## Edge cases

- [Webhooks] The same event is delivered twice: receivers can tell by its identifier
- [API access] A key is leaked: it can be revoked at once and the use before that is visible
- [Versions and limits] A client sends a huge request: it is refused before it uses resources

## Open questions

- [API access] Which actions and data does the API expose, and are there read-only keys?
- [Versions and limits] Which limits per key and per account, and how long is a version supported?
