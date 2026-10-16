<!-- name: Bevy (Rust ECS) -->
<!-- desc: Rust game on Bevy: one plugin per feature, small systems, components as data, states, asset loading -->

# STACK.md: Bevy (Rust ECS)

## Summary

A game in Rust on the Bevy engine using its Entity Component System: components are plain data, systems are small
functions that query them, and every feature is a `Plugin` that registers its own components, resources, systems and
events. Game states drive which systems run. Logic that does not need the ECS lives in plain modules and is unit tested.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Rust (stable, 2024 edition) | Performance and safety |
| Engine | Bevy 0.16 (pin the minor: Bevy breaks between minors) | Data-driven ECS, plugins |
| States | Bevy `States` / `SubStates` | Menus, loading, playing, paused |
| Assets | Bevy asset server + `bevy_asset_loader` | Declarative loading states |
| Input | `leafwing-input-manager` (or Bevy's `ButtonInput`) | Actions instead of raw keys |
| Physics | `avian2d`/`avian3d` when needed | ECS-native physics |
| Testing | `cargo test` with a headless `App` | Systems tested by running app updates |
| Lint/format | clippy (`-D warnings`) + rustfmt | |

## Project layout

```
Cargo.toml                       dev profile with opt-level = 1 for the game, 3 for dependencies
src/
  main.rs                        App::new() + DefaultPlugins + the game plugins, nothing else
  states.rs                      GameState enum (Loading, Menu, Playing, Paused)
  assets.rs                      asset collections loaded during GameState::Loading
  player/
    mod.rs                       PlayerPlugin: registers what is below
    components.rs                Player, Velocity, Health (data only)
    systems.rs                   move_player, apply_damage (small fns)
    events.rs                    PlayerDied, PlayerHit
  enemies/
    mod.rs                       EnemiesPlugin
    components.rs
    systems.rs
    spawn.rs
  ui/
    mod.rs                       UiPlugin (HUD, menus), reads components/events only
  rules/
    damage.rs                    pure functions (no Bevy types) with unit tests
assets/                          sprites, audio, fonts
tests/
  player_movement.rs             headless App, insert entities, run update(), assert components
```

Dependency direction: `main → plugins`; plugins communicate through events and shared components in `rules`-free
modules; `rules/` depends on nothing Bevy.

## Conventions

- One plugin per feature; `main.rs` only adds plugins.
- Components are plain data (`#[derive(Component)]`), no methods with game logic; resources for singletons.
- Systems are small and named by what they do; ordering expressed with system sets, never by registration order luck.
- Systems run in states (`.run_if(in_state(GameState::Playing))`); entering/exiting states spawns/despawns with markers.
- Features talk through events (`EventWriter`/`EventReader`), not by querying each other's internals.
- Every spawned entity gets a state-scoped marker so leaving the state cleans it up.
- Pure game math in `rules/` with unit tests.

## Commands

| Task | Command |
| --- | --- |
| Run | `cargo run` |
| Run (fast linking) | `cargo run --features bevy/dynamic_linking` |
| Test | `cargo test` |
| Lint | `cargo clippy --all-targets -- -D warnings` |
| Format | `cargo fmt` |
| Release build | `cargo build --release` |

## Testing

- `rules/` unit tests for all formulas.
- System tests: build a minimal headless `App` with the plugin under test (`MinimalPlugins`), spawn entities, call
  `app.update()`, assert on components, resources and events.
- A smoke test that the full app builds its schedule without conflicts.

## Quality gates

- `cargo clippy -D warnings`, `cargo fmt --check`, `cargo test` green.
- No system query ambiguity warnings in debug runs.

## Dependencies

- Allowed: Bevy, the ecosystem crates in the table, pinned to versions compatible with the Bevy minor.
- Do NOT use: crates not updated for the pinned Bevy version, `unsafe` for game logic, global statics instead of resources,
  giant systems that do several unrelated things.

## Rules for agents

- Add features as plugins in their own folder; register everything inside the plugin.
- Keep components as data only and logic in systems or `rules/`.
- Gate systems by state and order them with system sets.
- Communicate across features with events; never query another feature's private marker components.
- Tag every spawned entity with its state scope so it despawns on exit.
- Keep systems small (one job each) and name them by that job.
- Test systems in a headless `App` and pure rules with unit tests.
- Pin Bevy and its ecosystem crates to compatible versions; check compatibility before adding a crate.
- Never block the main thread with IO; use the asset server or async tasks.
