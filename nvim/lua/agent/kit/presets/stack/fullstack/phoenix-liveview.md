<!-- name: Phoenix LiveView -->
<!-- desc: Real-time server-rendered UI on Elixir: LiveView, function components, contexts, Ecto, LiveViewTest -->

# STACK.md: Phoenix LiveView

## Summary

An interactive web application with Phoenix LiveView: the server owns state and renders HTML, diffs travel over a
WebSocket, so rich UIs need almost no JavaScript. Business logic lives in **contexts**; LiveViews handle events by calling
one context function and assigning the result. PubSub gives real-time updates across users.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Elixir 1.18+ on Erlang/OTP 27 | Concurrency and fault tolerance |
| Web | Phoenix 1.7+ with LiveView 1.0+ | Server-rendered real-time UI |
| Components | Function components (`core_components.ex`) + HEEx | Reusable, type-checked attrs/slots |
| CSS | Tailwind (Phoenix default, esbuild/tailwind binaries, no Node) | Utility classes in HEEx |
| Data | PostgreSQL 16 + Ecto 3 | Changesets, migrations |
| Real-time | Phoenix PubSub + Presence | Broadcast changes to every viewer |
| Testing | ExUnit + `Phoenix.LiveViewTest` | Render and interact without a browser |
| Lint | `mix format`, Credo, Dialyzer | Idiomatic, checked |
| Deploy | Mix release in a container | One artifact |

## Project layout

```
lib/
  app/
    boards.ex                  Boards context (public API, broadcasts changes)
    boards/
      board.ex                 schema + changesets
      card.ex
  app_web/
    live/
      board_live/
        index.ex               LiveView: mount, handle_event, handle_info
        index.html.heex        template
        card_form_component.ex LiveComponent only when it needs its own state
    components/
      core_components.ex       buttons, inputs, modals, tables
      board_components.ex      domain components (card, column)
    router.ex
test/
  app/boards_test.exs
  app_web/live/board_live_test.exs
```

Dependency direction: `app_web → app`. LiveViews never call `Repo`; contexts broadcast on PubSub, LiveViews subscribe.

## Conventions

- `mount/3` assigns only what the first render needs; load lists with streams (`stream/3`) for large collections.
- One event = one context call; keep `handle_event` bodies short and pattern-matched.
- Function components first; LiveComponents only for isolated state.
- Forms with `to_form/1` and changesets; validation on `phx-change`, save on `phx-submit`.

## Commands

| Task | Command |
| --- | --- |
| Install | `mix setup` |
| Dev | `mix phx.server` |
| Test | `mix test` |
| Format | `mix format` |
| Lint | `mix credo --strict` |
| Migrate | `mix ecto.migrate` |
| Release | `MIX_ENV=prod mix assets.deploy && mix release` |

## Testing

- Context tests for rules; LiveView tests with `live/2`, `render_click`, `render_submit`, `assert_has`-style element checks.
- PubSub flows tested by broadcasting and asserting the re-render.

## Quality gates

- `mix format --check-formatted`, Credo strict, Dialyzer, `mix test --warnings-as-errors` all clean.

## Dependencies

- Phoenix, LiveView, Ecto, Tailwind/esbuild binaries.
- Do NOT use: a JS framework for UI that LiveView can render, `Repo` in LiveViews, LiveComponents for stateless markup.

## Rules for agents

- Keep business rules in contexts; LiveViews translate events to context calls and assigns.
- Use streams for collections that grow; never keep thousands of items in assigns.
- Every user-visible change made by one user is broadcast by the context, not by the LiveView.
- Declare `attr` and `slot` on every function component.
- Validate forms through changesets; never trust `params` directly.
- JavaScript hooks only for browser APIs LiveView cannot reach; one hook per behaviour.
- Test each LiveView's main events with `Phoenix.LiveViewTest`.
- Keep templates in `.heex` files next to their LiveView.
