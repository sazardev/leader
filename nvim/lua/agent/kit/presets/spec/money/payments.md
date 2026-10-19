<!-- name: Payments -->
<!-- desc: one-time payments: checkout, failures, receipts, refunds, idempotency, webhooks -->
<!-- for: all -->
<!-- needs: accounts -->

## Requirements

### Checkout

The system must let a person pay for something once, through the payment provider.

- Given an order, when they pay with valid details, then the payment is confirmed, the order is marked paid and they see a confirmation
- Given a declined payment, when it happens, then they see that it was declined with the provider's reason and can try another way
- Given a payment that needs an extra step (3-D Secure), when it happens, then they complete it and come back to the confirmation

### Receipts

The system must give a receipt for every successful payment.

- Given a successful payment, when it is confirmed, then a receipt with what was paid, the amount, taxes and the date is sent and kept in their account

### Refunds

The system must let the people allowed to do so refund a payment, fully or partly.

- Given a paid order, when an administrator refunds it, then the provider is asked to refund, the order shows it and the person is told
- Given a partial refund, when it is made, then the amount refunded and what remains are shown
- Given a refund the provider refuses, when it happens, then the order is unchanged and the reason is shown

## Edge cases

- [Checkout] Pay pressed twice or the request retried: the person is charged once (idempotency key per order)
- [Checkout] The provider's confirmation arrives before, after, or without the person returning to the app: the order ends paid either way
- [Refunds] Two refunds of the same payment at once: the total never exceeds what was paid
- [Checkout] Provider notifications (webhooks) arrive twice or out of order: each is handled once, in the right state

## Open questions

- [Checkout] Which payment provider and which methods (cards, wallets, bank transfer)?
- [Receipts] Which currencies and which taxes apply, in which countries?
- [Refunds] Who can refund, and up to how long after the payment?
