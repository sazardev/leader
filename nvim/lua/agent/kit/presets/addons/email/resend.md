<!-- name: Resend -->
<!-- desc: transactional email through the Resend API with React Email templates and verified domains -->
<!-- for: ts js node bun !mobile -->

## Stack

| Email | Resend (HTTP API, React Email templates, domain verified with SPF, DKIM and DMARC) | Simple API and good developer experience for transactional email |

## Project layout

```
src/email/send.ts              the one function that calls Resend (key, from address, error handling)
src/email/templates/           React Email components, one per message
```

## Conventions

- `RESEND_API_KEY` from the environment; the `from` address is on the verified domain, configured once.
- Every message has an HTML and a plain-text version; templates are components rendered in tests.
- Sending is asynchronous: enqueue from the request, send in a job with retries and an idempotency key.
- Only transactional mail through this path; marketing mail needs unsubscribe handling and a separate sender.
- Preview templates locally with `email dev` (React Email) before sending anything.

## Commands

| Email preview | `npx email dev` |

## Testing

- Tests replace the sender with a fake that records messages; assert recipient, subject and the link in the body.

## Rules for agents

- Never send from a test or development environment to real addresses; use a sandbox address or the fake sender.
- Never put the API key in client code.
- Never build recipients or headers from unvalidated input (header injection).
