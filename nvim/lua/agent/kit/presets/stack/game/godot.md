<!-- name: Godot 4 (GDScript) -->
<!-- desc: Godot 4 game in typed GDScript: scenes and nodes per feature, signals, autoloads kept small, GUT tests -->

# STACK.md: Godot 4 (GDScript)

## Summary

A 2D or 3D game built with Godot 4 and statically typed GDScript. Each feature is a folder with its scenes, scripts and
resources; nodes talk to their children by calling and to their parents by signals ("call down, signal up"). Game data
lives in custom `Resource` files, not in code. Rules that do not need the engine are plain classes tested with GUT.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | GDScript (Godot 4.4+, static typing on) | First-class in the editor, fast iteration |
| Engine | Godot 4 | Open source, scenes + nodes, 2D and 3D |
| Data | Custom `Resource` classes (`.tres`) | Designers edit stats in the inspector, versionable |
| Global state | A few autoloads (`Events`, `Save`, `Settings`) | Small, explicit singletons |
| Input | Input Map actions | Rebindable, no hardcoded keys |
| Testing | GUT (Godot Unit Test) | Unit and scene tests inside the engine |
| Lint/format | gdtoolkit (`gdlint`, `gdformat`) | Consistent style |
| Export | Godot export presets (`export_presets.cfg`) | One file per platform |

## Project layout

```
project.godot
features/
  player/
    player.tscn               scene root + child nodes
    player.gd                 movement and wiring only; emits signals
    player_stats.gd           class_name PlayerStats extends Resource (data)
    player_stats.tres
    states/                   one state per file when the player has a state machine
      idle_state.gd
      run_state.gd
  enemies/
    slime/slime.tscn
    slime/slime.gd
  ui/
    hud/hud.tscn
    hud/hud.gd                listens to Events, never reaches into gameplay nodes
core/
  events.gd                   autoload: game-wide signals only (no logic)
  save_game.gd                autoload: save/load to user://
  rules/
    damage.gd                 class_name Damage: pure functions, no Node
levels/
  level_01.tscn
assets/                       art, audio, fonts (imported)
tests/
  unit/test_damage.gd         GUT tests for core/rules
  scenes/test_player.gd       GUT scene tests
```

Dependency direction: levels instance features; features use `core/`; `core/rules` depends on nothing in the scene tree.

## Conventions

- Static typing everywhere: typed variables, parameters and returns; `class_name` for reusable scripts.
- Call down, signal up: a node calls methods on its children and emits signals to its parent; never `get_parent()` chains.
- `@export` for tunables and node references; never `get_node("../../X")` with long paths.
- Game rules (damage, scoring, inventory) are plain classes in `core/rules/`, not methods on nodes.
- Data (stats, items, levels' parameters) in `Resource` files; code reads them, never hardcodes numbers.
- Autoloads stay small: `Events` only declares signals; no gameplay logic in autoloads.
- Input through Input Map actions (`Input.is_action_pressed("jump")`), never raw keycodes.

## Commands

| Task | Command |
| --- | --- |
| Open editor | `godot --editor project.godot` |
| Run | `godot --path .` |
| Test | `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit` |
| Lint | `gdlint features core tests` |
| Format | `gdformat features core tests` |
| Export | `godot --headless --export-release "Linux" build/game.x86_64` |

## Testing

- Unit tests (GUT) for everything in `core/rules/` and resource validation.
- Scene tests: instance a scene, simulate input/frames with GUT helpers, assert on signals and state.
- A smoke test that loads every level scene without errors.

## Quality gates

- `gdlint` clean, `gdformat --check` clean, GUT green headless.
- No script errors or warnings in the editor's output for the main scenes; static typing warnings treated as errors.

## Dependencies

- Allowed: Godot built-ins, GUT, gdtoolkit; addons only from the Asset Library with a reason in the PR.
- Do NOT use: deep node paths (`get_node("../../..")`), logic in autoloads, untyped GDScript, C# mixed into a GDScript
  project without a reason, hardcoded tuning numbers in scripts.

## Rules for agents

- Use static typing in every script; give reusable scripts a `class_name`.
- Keep one scene + its script per feature folder; one state per file in state machines.
- Communicate upward with signals and downward with method calls; never walk parents.
- Put tunable numbers in `@export` vars or `Resource` files, never as literals in logic.
- Put game rules in `core/rules/` as plain classes and test them with GUT.
- Use Input Map actions for all input.
- Add new global signals to `core/events.gd` only when two unrelated features need them.
- Never edit `.import` files or anything in `.godot/` by hand.
- Run the headless GUT suite after every gameplay change.
