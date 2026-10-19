<!-- name: Session cookies -->
<!-- desc: your own sessions: random id in an HttpOnly cookie, server-side store, argon2id passwords, CSRF protection -->
<!-- for: server backend fullstack web selfhosted !game -->

## Stack

| Auth | Own sessions (opaque id in an HttpOnly cookie, server-side session table, argon2id password hashes, CSRF protection) | Simple, revocable, no tokens in the browser, no third party |

## Project layout

```
auth/passwords                 hash and verify with argon2id; rehash when parameters change
auth/sessions                  create, load, rotate and revoke sessions (table: id hash, user id, expires_at)
auth/csrf                      token or Origin check for every state-changing request
```

## Conventions

- Session id: at least 128 bits from a CSPRNG; store only its SHA-256 hash in the database.
- Cookie flags: `HttpOnly`, `Secure`, `SameSite=Lax` (or `Strict`), `Path=/`, a `__Host-` prefix in production.
- Rotate the id on login and privilege change; delete the row on logout; expire idle and absolute lifetimes.
- Every POST/PUT/PATCH/DELETE checks CSRF (a token, or `Origin`/`Sec-Fetch-Site`).
- Rate limit login and password reset per account and per IP; answer the same way whether the email exists or not.

## Testing

- Cover: wrong password, expired and revoked session, logout invalidates the cookie, CSRF rejected, session fixation (id changes on login).

## Rules for agents

- Never store passwords in plain text or with a fast hash (SHA, MD5); use argon2id.
- Never put user data or the user id as the cookie value without a server-side lookup.
- Never log cookies, passwords or reset tokens.
- Authorization (who may see this record) is checked in every handler, not only authentication.
