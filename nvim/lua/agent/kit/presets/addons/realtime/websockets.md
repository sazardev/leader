<!-- name: WebSockets -->
<!-- desc: own WebSocket server with auth on connect, heartbeats, typed messages and reconnecting clients -->
<!-- for: server backend fullstack web ui !tui -->

## Stack

| Realtime | WebSockets (own server endpoint, authenticated on connect, typed JSON messages, heartbeats) | Bidirectional low-latency messages under our control |

## Project layout

```
src/realtime/hub.ts            connections by user/room, broadcast, backpressure handling (name per language)
src/realtime/protocol.ts       message types and validation shared by server and client
```

## Conventions

- Authenticate during the handshake (cookie, or a short-lived ticket issued by an HTTP endpoint); never accept an anonymous socket and authenticate later.
- Check the `Origin` header against an allow-list; authorize every message and every room join, not only the connection.
- Messages are versioned typed envelopes (`{ type, id, payload }`) validated on receipt; unknown types are ignored or closed with a code.
- Server sends ping frames on an interval and drops connections that miss pongs; set a max message size and a rate limit per connection.
- Clients reconnect with exponential backoff and jitter and resync state (last event id) after reconnecting.
- Scaling out needs a pub/sub backplane (Redis or NATS) so a broadcast reaches sockets on every instance.

## Commands

| Socket probe | `npx wscat -c ws://localhost:8080/ws` |

## Testing

- Integration tests open real sockets against the server: handshake rejection, authorization, heartbeat timeout and reconnection.

## Rules for agents

- Never trust a user id or room sent in a message; derive identity from the authenticated connection.
- Never broadcast without checking each recipient may see the data.
- Never keep unbounded per-connection buffers; close slow consumers.
