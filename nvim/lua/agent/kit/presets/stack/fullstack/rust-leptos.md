<!-- name: Rust + Leptos -->
<!-- desc: full-stack Rust web app: Leptos SSR + hydration, server functions on Axum, cargo-leptos, Tailwind -->

# STACK.md: Rust + Leptos

## Summary

A full-stack web application written entirely in Rust with Leptos: pages render on the server (SSR, streaming) and
hydrate in the browser as WebAssembly with fine-grained reactivity (signals). Data moves through server functions
(`#[server]`), which run on Axum and are called from the client like async functions. The same crate compiles twice
(`ssr` and `hydrate` features) with cargo-leptos. Business logic lives in a separate crate with no Leptos imports.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Rust stable, edition 2024 | One language and type system for server and client |
| Framework | Leptos 0.8 (SSR + hydration, `leptos_router`) | Fine-grained reactivity, server functions, streaming SSR |
| Server | Axum via `leptos_axum` + tokio | Mature HTTP stack, middleware with tower |
| Build | `cargo-leptos` (server binary + WASM + CSS in one command) | Watch mode with hot reload |
| Styling | Tailwind CSS (standalone CLI, integrated by cargo-leptos) | Utility classes in `view!` markup |
| Database | PostgreSQL 16 + `sqlx` (server only) | Checked SQL, migrations |
| Auth | Server-side sessions (`tower-sessions`) + argon2 | No tokens in the browser |
| Errors | `thiserror` + `ServerFnError` at the boundary | Typed errors, clean client messages |
| Testing | `cargo test` (logic), `wasm-bindgen-test` (client), Playwright (end to end) | Each layer at its level |
| Lint | `cargo clippy -D warnings`, `cargo fmt`, `leptosfmt` for `view!` | Formatted markup too |
| Deploy | One container with the server binary and the `site/` folder | Single process |

## Project layout

```
Cargo.toml                    workspace + [package.metadata.leptos] (site root, tailwind input, features)
crates/
  domain/                     entities, rules, ports (traits); no leptos, no sqlx
  app/                        the Leptos crate (features: ssr, hydrate)
    src/lib.rs                App component, router, hydrate entry
    src/routes/               one page component per file (home.rs, orders/list.rs, orders/detail.rs)
    src/components/           reusable components (button.rs, data_table.rs)
    src/server/               #[server] functions, one area per file (orders.rs); call domain use cases
    src/state.rs              context types provided at the root (user session, theme)
  server/                     Axum main: config, pool, sessions, leptos_routes, static files (feature ssr)
  storage/                    sqlx repositories implementing domain ports
migrations/
style/tailwind.css
end2end/                      Playwright tests
```

Dependency direction: `server → app, storage → domain`. Code under `#[cfg(feature = "ssr")]` (DB pools, secrets) never
compiles into the WASM bundle.

## Conventions

- Components are functions returning `impl IntoView`; one page or component per file, props typed.
- Data loads with `Resource`/`Suspense` around server functions; mutations use `ServerAction` + `ActionForm` (works without JS).
- Server functions are thin: authenticate, validate, call one domain use case, map the error.
- Server-only imports live behind `#[cfg(feature = "ssr")]`; check both builds compile (`cargo leptos build`).
- Signals hold UI state only; the server is the source of truth for data.
- New page = route in `lib.rs` + component in `routes/` + its server functions + a Playwright test.

## Commands

| Task | Command |
| --- | --- |
| Dev | `cargo leptos watch` |
| Build | `cargo leptos build --release` |
| Test | `cargo test --workspace` |
| End-to-end | `cargo leptos end-to-end` |
| Lint | `cargo clippy --workspace --all-features -- -D warnings` |
| Format | `cargo fmt && leptosfmt crates/app/src` |
| Migrate | `sqlx migrate run` |

## Testing

- Domain: unit tests. Storage: sqlx tests against Postgres (testcontainers).
- Server functions: call them as plain async functions in `ssr` tests with a test context.
- Components with logic: `wasm-bindgen-test` in a headless browser.
- Main flows: Playwright in `end2end/` against `cargo leptos serve`.

## Quality gates

- `cargo fmt --check`, `leptosfmt --check`, clippy with `-D warnings` for both `ssr` and `hydrate` features.
- Tests and end-to-end green; WASM bundle size tracked in CI (fail on a large jump).

## Dependencies

- Leptos ecosystem crates matching the Leptos version; server crates only under `ssr`.
- Do NOT use: a JS framework next to Leptos, `reqwest` from the client to your own server (use server functions), heavy crates in the `hydrate` build (every dependency grows the WASM), `unwrap()` in server functions.

## Rules for agents

- Never import DB, filesystem or secret-handling crates outside `#[cfg(feature = "ssr")]`.
- Every server function authenticates and validates its input; treat it as a public endpoint.
- Never put business rules in components or server functions; they live in `domain`.
- Use `ActionForm` for mutations so forms work before hydration.
- Keep hydration consistent: no `rand`, time or browser-only APIs during the server render.
- Every new page gets a Playwright test of its main flow.
- Check bundle size impact before adding a dependency to the `hydrate` build.
- Format `view!` macros with leptosfmt; keep components small and one per file.
