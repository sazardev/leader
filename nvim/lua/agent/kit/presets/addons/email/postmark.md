<!-- name: Postmark -->
<!-- desc: transactional email with Postmark: dedicated message stream, templates, bounce and spam webhooks -->
<!-- for: server backend fullstack web selfhosted !game -->

## Stack

| Email | Postmark (transactional message stream, server API token, SPF + DKIM, bounce webhooks) | High deliverability and fast delivery for password resets and receipts |

## Project layout

```
email/sender                   the one module that calls the Postmark API (token, From, message stream)
email/templates/               templates, versioned in the repo (HTML + text)
email/webhooks                 bounce, spam complaint and delivery events
```

## Conventions

- `POSTMARK_SERVER_TOKEN` from the environment; one server per environment, and `MessageStream` set explicitly (`outbound`).
- Send only transactional mail; marketing goes to a broadcast stream.
- The bounce and spam-complaint webhooks mark the address as suppressed in your database; never send to it again.
- Send from a job with retries, passing a stable `Metadata` id so a retry is traceable.
- Verify the sending domain (SPF, DKIM, return-path) before going live.

## Testing

- Unit tests use a fake sender; Postmark's `POSTMARK_API_TEST` token accepts calls without delivering them.

## Rules for agents

- Never send to a suppressed address or ignore bounce events.
- Never include secrets or one-time tokens in logs; reset links expire and are single use.
- Never put the server token in client code.
