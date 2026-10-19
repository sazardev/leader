<!-- name: Auth.js -->
<!-- desc: Auth.js (NextAuth) for web apps: OAuth and credentials providers, database adapter, server-side sessions -->
<!-- for: ts js node !mobile -->

## Stack

| Auth | Auth.js (`next-auth` v5: OAuth providers, database adapter, JWT or database sessions) | The common choice for Next.js and SvelteKit apps with social sign-in |

## Project layout

```
auth.ts                        `NextAuth({...})` config: providers, adapter, callbacks; exports `auth`, `signIn`, `signOut`, `handlers`
middleware.ts                  route protection using `auth`
app/api/auth/[...nextauth]/route.ts   re-exports `handlers` (GET, POST)
```

## Conventions

- `AUTH_SECRET` and every provider id/secret come from environment variables; `AUTH_TRUST_HOST` only behind a trusted proxy.
- Use a database adapter for users and accounts when data must outlive a token; otherwise JWT sessions stay small.
- Add the user id and role to the session in the `jwt` and `session` callbacks, and read them only on the server.
- Authorize in every server action and route handler with `await auth()`; middleware alone is not a guard.
- Credentials provider: hash with argon2id or bcrypt, rate limit, never reveal whether the email exists.

## Commands

| Secret | `npx auth secret` |

## Testing

- Unit-test the `authorize` function and the callbacks; end-to-end tests sign in with a seeded test user (cookie stored once, reused).

## Rules for agents

- Never read the user from the client (`useSession`) to authorize a server action.
- Never put secrets in `NEXT_PUBLIC_*` variables.
- Never trust the `callbackUrl` without checking it is a relative or allowed URL.
