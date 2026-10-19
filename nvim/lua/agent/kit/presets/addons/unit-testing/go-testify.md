<!-- name: Go testing + testify -->
<!-- desc: standard `testing` with table-driven tests, testify assertions, race detector and coverage -->
<!-- for: go -->

## Stack

| Unit tests | Go `testing` with table-driven subtests and `stretchr/testify` (`require`, `assert`) | Standard tooling plus readable assertions |

## Project layout

```
internal/<pkg>/<file>_test.go  tests next to the code, same package for white-box, `<pkg>_test` for the public API
internal/testutil/             builders, fixtures, fake clock and fake clients shared by tests
testdata/                      golden files and sample inputs (ignored by the Go tool)
```

## Conventions

- Table-driven: `tests := []struct{ name string; ...; want ... }{...}` and `t.Run(tt.name, func(t *testing.T) { ... })`.
- `require` for conditions that make the rest meaningless (errors, nil), `assert` for independent checks; expected first, actual second.
- Mark helpers with `t.Helper()`, use `t.Cleanup` for teardown, `t.TempDir()` for files and `t.Setenv` for environment.
- Parallel tests call `t.Parallel()` and capture the loop variable correctly for the Go version in `go.mod`.
- Depend on small interfaces defined by the consumer and use hand-written fakes; mocks (`testify/mock`) only when behaviour must be verified.
- Time comes from an injected clock, never `time.Now()` inside logic under test.
- Golden files are updated with an explicit flag and the diff is reviewed.

## Commands

| Test | `go test ./...` |
| Test race | `go test -race -count=1 ./...` |
| Coverage | `go test -coverprofile=coverage.out ./... && go tool cover -func=coverage.out` |

## Quality gates

- `go test -race ./...` passes.

## Rules for agents

- Every bug fix and new function gets a test that fails without the change.
- Never delete or `t.Skip` a failing test to get green; fix the cause.
- Never rely on `time.Sleep` for synchronization; use channels, `sync.WaitGroup` or `Eventually` with a timeout.
