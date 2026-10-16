<!-- name: Go SSH app (Wish) -->
<!-- desc: TUI served over SSH with Charm Wish + Bubble Tea: public-key auth, per-session programs, host keys -->

# STACK.md: Go SSH app (Wish)

## Summary

A TUI application served over SSH: users run `ssh app.example.com` and get an interactive terminal app, no client to
install. Charm's Wish is the SSH server; its Bubble Tea middleware starts one Bubble Tea program per session, sized to
that session's PTY. Users are identified by their SSH public key. The domain and storage are plain Go behind ports; each
SSH session is just another adapter in front of them.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Go 1.25+ | One static binary, cheap goroutine per session |
| SSH server | `github.com/charmbracelet/wish` (on `gliderlabs/ssh`) | Middleware chain: logging, auth, rate limit, Bubble Tea |
| TUI | `bubbletea` + `bubbles` + `lipgloss` via `wish/bubbletea` middleware | One program per session with its own renderer |
| Auth | Public-key auth (`ssh.PublicKeyHandler`), keys mapped to users in the DB | No passwords; identity is the key fingerprint |
| Host keys | ed25519 key generated once in a persistent volume (`wish.WithHostKeyPath`) | Clients keep trusting the server across deploys |
| Storage | SQLite (`modernc.org/sqlite`, WAL) or Postgres via `pgx` | SQLite is enough for one server |
| Config | env vars → typed struct | 12-factor |
| Logging | `log/slog` (JSON) + `wish/logging` middleware | Per-session logs with user and remote address |
| Testing | `testing` + `teatest` for screens + an in-process SSH client (`golang.org/x/crypto/ssh`) | Real sessions in tests |
| Lint | golangci-lint v2 | One config, many linters |
| Deploy | One container exposing port 22 (or 2222), host key on a volume | Nothing else to run |

## Project layout

```
cmd/server/main.go               config, DB, stores, wish.NewServer(...) with the middleware chain, graceful shutdown
internal/
  domain/                        users, rooms/items… and their rules; ports (UserStore…); no SSH or UI imports
  storage/sqlite/                implements the ports
  sshd/
    server.go                    builds the wish server: host key, address, idle/max timeouts
    auth.go                      public-key handler: fingerprint → user (or registration flow)
    middleware.go                rate limit, active-session limit, recovery
    session.go                   per-session handler: reads PTY size, user, builds the root model
  ui/
    app.go                       root model for one session (user, window size, active screen)
    styles.go                    styles built from the session's renderer (bubbletea.MakeRenderer)
    screens/<name>/{model,update,view}.go
  bus/                           broadcasts events between sessions (chat, presence) through channels → messages
data/                            volume: SQLite file + host key (git-ignored)
```

Dependency direction: `cmd → sshd → ui → domain ← storage`. The UI never touches `ssh.Session`; `sshd/session.go`
extracts what it needs (user, size, renderer) and passes it in.

## Conventions

- Styles are created from the session's renderer (`bubbletea.MakeRenderer(s)`), never from the global one: each client has its own color profile.
- Everything shared between sessions (presence, chat, live updates) goes through `bus/` and arrives in each program as a message via `p.Send`.
- Each session has idle and absolute timeouts; a disconnect cancels its context and every command started for it.
- Users are looked up by key fingerprint (SHA256); an unknown key gets the registration screen or is rejected, by config.
- Commands without a PTY (`ssh app.example.com stats`) are handled by a separate non-interactive handler, not the TUI.
- New screen = folder under `ui/screens/` + messages + route in `app.go` + a teatest test.

## Commands

| Task | Command |
| --- | --- |
| Run | `go run ./cmd/server` then `ssh -p 23234 localhost` |
| Build | `CGO_ENABLED=0 go build -o bin/server ./cmd/server` |
| Test | `go test -race ./...` |
| Lint | `golangci-lint run` |
| Format | `gofmt -w .` |
| Container | `docker build -t app . && docker run -p 2222:23234 -v app-data:/data app` |

## Testing

- Domain and storage: unit tests with SQLite in a temp dir.
- Screens: teatest with a fixed size and the ASCII color profile, compared with golden files.
- SSH: start the server on a random port in the test, connect with `x/crypto/ssh` using generated keys, request a PTY, send keys, assert on output; test auth accept/reject.
- Concurrency: tests with several sessions at once under `-race` (broadcasts, disconnects mid-command).

## Quality gates

- `gofmt` clean, golangci-lint with zero issues (gosec enabled), `go test -race ./...` green.
- Host key and DB paths come from config and are never inside the image.

## Dependencies

- Charm (wish, bubbletea, bubbles, lipgloss), `x/crypto/ssh` for tests, the standard library for the rest.
- Do NOT use: password authentication, the global lipgloss renderer in session code, `os.Stdout` (it is the server's terminal, not the user's), a host key generated at every start.

## Rules for agents

- Never read or write `os.Stdin`/`os.Stdout` in server code; each session's IO is its `ssh.Session`.
- Always create styles from the session renderer; a global style leaks one client's color profile into others.
- Never trust the SSH username for identity; identity is the public key fingerprint.
- Every session goroutine and command must stop when the session context is cancelled.
- Cross-session events go through `bus/` as messages; never mutate another session's model.
- Keep the host key on a persistent volume and out of git; never regenerate it on deploy.
- Rate-limit connections and cap concurrent sessions per key in middleware.
- Add a teatest golden test for each new screen and an SSH integration test for each new auth or command path.
