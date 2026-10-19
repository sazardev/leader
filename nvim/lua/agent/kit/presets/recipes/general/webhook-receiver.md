<!-- name: Webhook receiver -->
<!-- desc: an endpoint that verifies the signature, answers fast, processes once and rejects replays -->
<!-- for: server -->
<!-- input: provider | Who sends the webhooks (e.g. Stripe, GitHub, Twilio) -->
<!-- input: events | The events to handle and what each does (e.g. invoice.paid: mark the order paid) -->

# Recipe: {{provider}} webhooks

Events: {{events}}.

## Make

- A POST route for {{provider}} on the project's server, registered where the others are, reading the raw body (before any JSON parsing) because the signature covers the exact bytes.
- Signature verification as {{provider}} documents it (its SDK helper when there is one), comparing in constant time, with the secret from the environment and listed in the example env file.
- A handler per event in {{events}}, kept apart from the route; unknown events are logged and acknowledged.
- Idempotent processing: store each event id on receipt (a unique key) and skip the ones already seen; effects are safe to run twice.
- A fast answer: 2xx as soon as the event is verified and stored, with the real work done in the project's background jobs (or after the response when the stack has no queue); 4xx for a bad signature, 5xx only when the event could not be stored so the sender retries.

## Rules

- Nothing from the payload is trusted before the signature passes; no secrets or full payloads in logs.
- Replay protection: reject events whose timestamp is outside the tolerance the provider documents (usually 5 minutes) and ids already processed.
- Events can arrive late or out of order: handlers check the current state of the record before changing it.
- Follow the existing routes: naming, error helper, logging.

## Tests

- A valid signature is accepted and its handler runs; a wrong, missing or modified-body signature is rejected with no effect.
- The same event delivered twice has the effect once; an old timestamp is rejected.
- An unknown event answers 2xx; a handler failure leaves the event retryable.
