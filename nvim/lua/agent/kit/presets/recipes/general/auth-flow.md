<!-- name: Authentication flow -->
<!-- desc: sign up, sign in, sign out, password reset, email verification, protected routes, rate limiting -->
<!-- for: server ui -->
<!-- input: methods | How people sign in (e.g. email + password, Google) -->

# Recipe: authentication with {{methods}}

## Make

- Use the auth STACK.md's Auth row names (a library, a managed service, the framework's own); no hand-rolled crypto. If the row is empty, take the simplest well-known option for the stack and say so.
- The flows for {{methods}}: sign up, sign in, sign out, and, for passwords, reset by a one-time link and email verification before the account is fully active.
- Sessions: how they are stored (secure cookie or token), their lifetime, and what happens when one expires (the user returns to sign in and then to the page they wanted).
- Protected routes: one guard, middleware or dependency that every private route uses, and the current user available to handlers and screens.
- The screens or forms for each flow with loading, field errors and a clear failure message; a link between sign in, sign up and reset.
- Rate limiting on sign in, sign up and reset (per IP and per account) with a retry message.

## Rules

- Passwords hashed with the library's recommended algorithm (argon2id or bcrypt); never logged, never returned.
- One generic message for a wrong email or password; reset never reveals whether an account exists.
- Reset and verification tokens are single use, expire (1 hour or less) and are stored hashed.
- Cookies are HttpOnly, Secure and SameSite; state-changing requests are protected against CSRF as the stack does it.
- Secrets and provider keys come from the environment, listed in the example env file.

## Tests

- Sign up, sign in and sign out end to end; a wrong password; a protected route with and without a session.
- Reset: a valid token, an expired token, a reused token.
- An expired session sends the user to sign in; the rate limit answers after too many attempts.
