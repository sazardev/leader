<!-- name: Stripe -->
<!-- desc: card and subscription payments with Stripe Checkout, signed webhooks and idempotency keys -->
<!-- for: server backend fullstack web selfhosted !game -->

## Stack

| Payments | Stripe (Checkout Sessions, Customer Portal, signed webhooks, idempotency keys) | Hosted payment pages keep card data out of the app |

## Project layout

```
payments/checkout              creates the Checkout Session for a plan or cart (server side only)
payments/webhooks              verifies the signature and applies events to the database
payments/events                one handler per event type, idempotent on `event.id`
```

## Conventions

- `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET` come from environment variables; test mode keys in development and CI.
- Amounts are integers in the smallest currency unit; prices and products are defined in Stripe and referenced by id.
- The database is updated from webhooks (`checkout.session.completed`, `invoice.paid`, `customer.subscription.updated`/`deleted`), never from the success redirect.
- Webhook handlers verify the signature against the raw body, store processed event ids and answer 2xx quickly; slow work goes to a queue.
- Every create call that must not run twice sends an `Idempotency-Key`.
- Store the Stripe customer id on your user; never card numbers.

## Commands

| Listen | `stripe listen --forward-to localhost:3000/webhooks/stripe` |
| Trigger | `stripe trigger checkout.session.completed` |

## Testing

- Use test mode and the Stripe CLI to replay events; test duplicate delivery, out-of-order events and an invalid signature.

## Rules for agents

- Never handle or log raw card data; use Checkout or Elements.
- Never trust the amount or price sent by the client; compute or look it up on the server.
- Never skip webhook signature verification or parse the body before verifying.
- Never use a live key outside production.
