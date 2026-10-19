<!-- name: Lemon Squeezy -->
<!-- desc: merchant of record for digital products and subscriptions: it handles VAT and sales tax for you -->
<!-- for: ts js node !mobile !game -->

## Stack

| Payments | Lemon Squeezy (merchant of record: hosted checkout, tax handled for you, signed webhooks) | Sell worldwide without registering for sales tax or VAT yourself |

## Project layout

```
payments/checkout              builds a checkout URL for a variant with the user's id in custom data
payments/webhooks              verifies the `X-Signature` HMAC and applies the event
```

## Conventions

- `LEMONSQUEEZY_API_KEY`, `LEMONSQUEEZY_STORE_ID` and `LEMONSQUEEZY_WEBHOOK_SECRET` come from environment variables; use test mode in development.
- Pass your own user id as checkout custom data and read it back from the webhook to link the order.
- Access is granted and revoked from webhooks (`order_created`, `subscription_created`, `subscription_updated`, `subscription_expired`), not from the redirect.
- Verify `X-Signature` (HMAC-SHA256 of the raw body) and process each event once.
- Subscription status and renewal date are stored locally; the customer portal URL comes from the subscription object.

## Testing

- Replay stored webhook payloads in tests; cover a bad signature, a repeated event and a cancelled subscription.

## Rules for agents

- Never skip the signature check or parse the body before verifying it.
- Never unlock a product because the browser returned to a success URL.
- Never expose the API key to the client.
