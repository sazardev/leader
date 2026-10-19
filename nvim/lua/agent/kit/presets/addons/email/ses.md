<!-- name: Amazon SES -->
<!-- desc: low-cost email on AWS SES: verified identity, IAM least privilege, bounce and complaint handling -->
<!-- for: server backend fullstack web selfhosted !game -->

## Stack

| Email | Amazon SES (v2 API, verified domain identity with DKIM, SNS events for bounces and complaints) | Cheapest at volume and already inside AWS |

## Project layout

```
email/sender                   the one module that calls `SendEmail` (region, from address, configuration set)
email/events                   SNS or EventBridge handler for bounces and complaints
```

## Conventions

- Credentials come from the runtime's IAM role, not static keys; the policy allows only `ses:SendEmail` on the identity in use.
- Send through a configuration set that publishes bounce, complaint and delivery events.
- Suppress an address in your own database on a hard bounce or complaint; keep the bounce rate low or SES pauses the account.
- Accounts start in the sandbox: request production access before launch.
- Development points at the local mail catcher or the SES mailbox simulator addresses, never real users.

## Testing

- Unit tests use a fake sender; integration tests use the SES mailbox simulator (`success@simulator.amazonses.com`, `bounce@simulator.amazonses.com`).

## Rules for agents

- Never commit AWS access keys or grant `ses:*` on `*`.
- Never send to an address that bounced before.
- Never build the sender address from user input.
