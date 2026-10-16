<!-- name: LÖVE 2D (Lua) -->
<!-- desc: 2D game in Lua with LÖVE: a state stack, entities as plain tables, systems per file, busted tests -->

# STACK.md: LÖVE 2D (Lua)

## Summary

A small 2D game written in Lua with the LÖVE framework. A state stack (menu, play, pause) owns the game loop callbacks;
entities are plain tables, behaviour lives in systems (one file each) that update and draw them. Everything that is not
drawing or input is plain Lua without `love.*` calls, so it is tested with busted outside the engine.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | Lua 5.1 / LuaJIT (LÖVE 11.5) | What LÖVE runs; fast with LuaJIT |
| Framework | LÖVE 11.5 | Graphics, audio, input, filesystem |
| States | Own small state stack (`push`/`pop`/`switch`) | Explicit, testable |
| Classes | Plain tables + metatables (or `classic`) | No heavy OOP |
| Tweens/timers | `flux` + own timer (or `hump.timer`) | Animations without logic in draw |
| Testing | busted | Pure modules tested in plain Lua |
| Lint/format | luacheck + StyLua | |
| Packaging | `.love` zip + `love.js` / platform fused builds | |

## Project layout

```
main.lua                      only wires love callbacks to the state stack
conf.lua                      window, identity, modules
src/
  core/
    state_stack.lua           push/pop/switch, forwards update/draw/keypressed
    input.lua                 action map: keys/gamepad → actions
    assets.lua                loads images/sounds once, by name
    timer.lua
  states/
    menu.lua                  one state per file: enter/exit/update/draw/keypressed
    play.lua
    pause.lua
  entities/
    player.lua                constructor returning a plain table (data only)
    enemy.lua
  systems/
    movement.lua              update(entities, dt) — pure, no love.*
    collision.lua             AABB tests — pure
    render.lua                the only system that calls love.graphics
  rules/
    scoring.lua               pure functions
assets/
spec/
  systems/movement_spec.lua   busted specs for pure modules
  rules/scoring_spec.lua
```

Dependency direction: `main → core/state_stack → states → systems → entities/rules`; only `render.lua`, `assets.lua`,
`input.lua` and `main.lua` touch `love.*`.

## Conventions

- One module per file returning a table; no globals (luacheck enforces it).
- Entities are data tables; systems hold the behaviour and take `dt` explicitly.
- Only render, input and asset modules call `love.*`; everything else is plain Lua and testable.
- Fixed timestep for physics/movement (accumulator in `play.lua`), rendering interpolated.
- Assets are loaded once in `assets.lua` and fetched by name; never `love.graphics.newImage` inside update/draw.
- Input goes through action names (`input.down("jump")`), never raw key checks in states.

## Commands

| Task | Command |
| --- | --- |
| Run | `love .` |
| Test | `busted` |
| Lint | `luacheck src spec` |
| Format | `stylua src spec` |
| Package | `zip -9 -r build/game.love . -x '*.git*' 'spec/*' 'build/*'` |

## Testing

- busted specs for systems (movement, collision), rules and the state stack, with `love` stubbed where unavoidable.
- A manual smoke checklist for each state (enter, play, pause, exit) before a release.

## Quality gates

- `luacheck` clean (no globals, no unused), `stylua --check` clean, `busted` green.

## Dependencies

- Allowed: LÖVE, small pure-Lua libraries vendored in `lib/` with their license (flux, classic, hump pieces).
- Do NOT use: globals for game state, `love.*` calls inside systems other than render, loading assets per frame,
  large frameworks for what a 50-line module does.

## Rules for agents

- Never create globals; every module returns a table and is required where used.
- Keep `love.*` calls in `main.lua`, `render.lua`, `input.lua` and `assets.lua` only.
- Put behaviour in systems (one per file) and keep entities as plain data tables.
- Pass `dt` explicitly; use the fixed timestep for movement and physics.
- Load assets once through `assets.lua`.
- Map input to actions in `input.lua`; states read actions, not keys.
- Write busted specs for every pure module you add or change.
- Keep one state per file with `enter`, `exit`, `update`, `draw` and input handlers.
- Run luacheck, StyLua and busted before finishing.
