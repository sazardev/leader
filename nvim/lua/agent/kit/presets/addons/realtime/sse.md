<!-- name: Server-Sent Events -->
<!-- desc: one-way server push over plain HTTP with EventSource, automatic reconnect and Last-Event-ID -->
<!-- for: server backend fullstack web ui !tui -->

## Stack

| Realtime | Server-Sent Events (`text/event-stream` over HTTP, `EventSource` in the browser, `Last-Event-ID` resume) | Simple one-way push that works through proxies and needs no extra protocol |

## Project layout

```
src/realtime/stream.ts         the event-stream endpoint: auth, subscribe, write events, heartbeat (name per language)
src/realtime/bus.ts            publish/subscribe inside the process, or Redis pub/sub across instances
```

## Conventions

- Response headers: `Content-Type: text/event-stream`, `Cache-Control: no-cache`, `Connection: keep-alive`; disable proxy buffering (`X-Accel-Buffering: no` on nginx).
- Every event has an `id`, an `event` name and a JSON `data` line; on reconnect the server replays what the client missed from `Last-Event-ID`.
- Send a comment line (`: ping`) every 15-30 seconds so proxies do not close idle streams.
- Authenticate with the session cookie (`EventSource` cannot set headers); clients send commands through normal HTTP requests.
- Detect client disconnects and unsubscribe immediately to avoid leaking listeners.
- Browsers limit connections per origin on HTTP/1.1; serve over HTTP/2 or share one stream per tab.

## Commands

| Stream probe | `curl -N -H "Accept: text/event-stream" http://localhost:8080/events` |

## Testing

- Tests read the stream with a real HTTP client: initial events, replay after `Last-Event-ID`, heartbeat and cleanup on disconnect.

## Rules for agents

- Never put tokens in the query string of the stream URL.
- Never send events a user is not allowed to see; filter per subscriber on the server.
- Never keep a subscriber after its connection closed.
