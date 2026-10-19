<!-- name: cargo-nextest -->
<!-- desc: faster, isolated Rust test runs with cargo-nextest, retries, profiles and JUnit output -->
<!-- for: rust -->

## Stack

| Unit tests | cargo-nextest (`.config/nextest.toml`, one process per test) plus `cargo test --doc` for doctests | Faster runs, clear output, per-test isolation and retries for flaky tests |

## Project layout

```
.config/nextest.toml           profiles (default, ci): retries, slow-timeout, fail-fast, JUnit output
src/**.rs                      unit tests in `#[cfg(test)] mod tests` next to the code
tests/                         integration tests, one file per feature, using only the public API
```

## Conventions

- Unit tests live in the same file as the code; integration tests in `tests/` use the crate as a user would.
- Each test is independent: nextest runs one process per test, so no test may rely on global state set by another.
- Name tests after behaviour (`rejects_expired_token`); use `#[should_panic(expected = "...")]` or `Result`-returning tests instead of `unwrap` noise.
- The `ci` profile enables `retries` only where flakiness is documented and sets a `slow-timeout`; JUnit output goes to `target/nextest/ci/junit.xml`.
- Doctests are not run by nextest: run `cargo test --doc` in the same CI step.
- Property tests (`proptest`) for parsers and invariants; snapshot tests (`insta`) for stable output, reviewed with `cargo insta review`.

## Commands

| Test | `cargo nextest run` |
| Test CI | `cargo nextest run --profile ci && cargo test --doc` |

## Quality gates

- `cargo nextest run --profile ci` and `cargo test --doc` pass.

## Rules for agents

- Every bug fix and new function gets a test that fails without the change.
- Never mark a test `#[ignore]` to get green without a written reason and an issue.
- Never use real network, clock or shared files in unit tests.
