<!-- name: Ably -->
<!-- desc: hosted pub/sub channels with presence and history; the server issues scoped token requests -->
<!-- for: ts js web ui fullstack backend server mobile !tui -->

## Stack

| Realtime | Ably (hosted pub/sub channels, presence, message history, token authentication) | Global realtime delivery without running or scaling socket servers |

## Project layout

```
src/realtime/ably.ts           server client (REST, API key) and the createTokenRequest endpoint logic
src/realtime/channels.ts       channel names and capability rules in one place
.env.example                   ABLY_API_KEY (server only, placeholder)
```

## Conventions

- Clients never hold the API key; they authenticate with `authUrl` / `authCallback` that returns a token request from our server.
- Token capabilities are minimal and per user (`{ "orders:<userId>": ["subscribe"] }`) with a short TTL.
- Channel names come from one helper (`orders:<id>`, `chat:<room>`); no string concatenation in call sites.
- The database stays the source of truth: publish after the write commits, and let clients refetch on reconnect or use channel history for gaps.
- Messages are small typed JSON; large data is fetched by id over HTTP.

## Commands

| Realtime check | `curl -u "$ABLY_API_KEY" https://rest.ably.io/time` |

## Testing

- Application code depends on a small publish/subscribe interface; tests use an in-memory fake, not the hosted service.

## Rules for agents

- Never ship `ABLY_API_KEY` to a browser or mobile app; only token requests.
- Never grant wildcard capabilities (`*`) to end users.
- Never rely on presence or channel messages as proof of identity or authorization.
