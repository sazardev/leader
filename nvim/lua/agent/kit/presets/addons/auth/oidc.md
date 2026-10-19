<!-- name: OpenID Connect -->
<!-- desc: sign-in through an OpenID Connect / OAuth2 provider (Keycloak, Auth0, Entra ID): code flow with PKCE -->
<!-- for: server backend fullstack web selfhosted !game -->

## Stack

| Auth | OpenID Connect / OAuth2 (authorization code flow with PKCE; Keycloak, Auth0, Entra ID or any compliant provider) | One identity provider for every app, standard tokens, no passwords stored here |

## Project layout

```
auth/oidc                      discovery, login redirect, callback, token validation, logout
auth/middleware                validates the session or bearer token and attaches the user
```

## Conventions

- Issuer, client id and redirect URI come from configuration; the client secret from a secret store, never the repository.
- Use the authorization code flow with PKCE and a `state` and `nonce` checked on the callback; never the implicit flow.
- Load keys from the provider's discovery document (`/.well-known/openid-configuration`) and cache the JWKS.
- APIs validate `iss`, `aud`, `exp` and the signature on every access token; roles come from claims, mapped in one place.
- Sessions for browsers are HttpOnly cookies; tokens are never kept in `localStorage`.

## Testing

- Test token validation with locally signed tokens (wrong audience, expired, wrong issuer, tampered); end-to-end tests use a local provider container such as Keycloak.

## Rules for agents

- Never accept a token without verifying signature, issuer, audience and expiry.
- Never decode a JWT and trust it without verifying it.
- Never log tokens or put them in URLs.
- Redirect URIs are matched exactly, never by prefix.
