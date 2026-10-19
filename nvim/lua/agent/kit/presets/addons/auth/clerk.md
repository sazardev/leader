<!-- name: Clerk -->
<!-- desc: hosted auth and user management: prebuilt sign-in UI, sessions, organizations, webhooks -->
<!-- for: ts js node !game -->

## Stack

| Auth | Clerk (hosted; prebuilt components, session tokens verified on the server, webhooks for user sync) | No auth backend to run: UI, MFA, social sign-in and organizations included |

## Project layout

```
middleware.ts                  `clerkMiddleware()` with the route matcher for protected routes
src/lib/auth.ts                helpers around `auth()` that return the userId or throw
src/app/api/webhooks/clerk/    webhook endpoint: verifies the signature, syncs users to the database
```

## Conventions

- Keys come from environment variables (`NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` is public, `CLERK_SECRET_KEY` is not); development and production use separate instances.
- Authorize on the server with `auth()` in every route handler and server action; never from client state.
- Store only the Clerk `userId` as the foreign key in your tables; copy profile fields through webhooks if needed.
- Webhooks verify the signature (Svix) and are idempotent on the event id.

## Commands

| Tunnel | `npx svix listen http://localhost:3000/api/webhooks/clerk` |

## Testing

- Tests use a Clerk development instance with test users, or mock `auth()` at the boundary in unit tests.

## Rules for agents

- Never expose `CLERK_SECRET_KEY` to the client or commit it.
- Never skip webhook signature verification.
- Never accept a user id from the request body.
