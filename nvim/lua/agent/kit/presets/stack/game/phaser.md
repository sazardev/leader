<!-- name: Phaser 3 (TypeScript + Vite) -->
<!-- desc: browser game with Phaser 3, TypeScript and Vite: a scene per screen, prefabs, typed asset keys -->

# STACK.md: Phaser 3 (TypeScript + Vite)

## Summary

A browser game built with Phaser 3 in TypeScript and bundled by Vite. Each screen is a Scene (boot, preload, menu, game,
UI overlay); game objects are prefabs (classes extending Phaser objects) in their own files; game rules that do not need
Phaser are plain TypeScript tested with Vitest. Asset keys are typed constants, never loose strings.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc`, strict) | Typed scenes, prefabs and events |
| Engine | Phaser 3.90 | Mature 2D web engine (Arcade physics, tweens, input) |
| Bundler | Vite 8 | Fast dev server, asset handling |
| Physics | Arcade Physics (Matter only when needed) | Simple and fast |
| Testing | Vitest (rules, pure logic) + Playwright smoke (boots, reaches menu) | |
| Package manager | pnpm | |
| Lint/format | ESLint (typescript-eslint strict) + Prettier | |
| Deploy | Static hosting of `dist/` (itch.io, Pages) | |

## Project layout

```
index.html
src/
  main.ts                      Phaser.Game config: scenes list, scale mode, physics
  scenes/
    BootScene.ts               minimal assets for the loading bar
    PreloadScene.ts            loads everything listed in assets/keys.ts
    MenuScene.ts
    GameScene.ts               creates prefabs, wires events, no rules inside
    UiScene.ts                 HUD overlay running in parallel, listens to events
  prefabs/
    Player.ts                  class Player extends Phaser.Physics.Arcade.Sprite
    Enemy.ts
  systems/
    Spawner.ts                 one responsibility per file
    Collisions.ts
  rules/
    scoring.ts                 pure functions
    waves.ts
  assets/
    keys.ts                    `as const` maps of texture/audio/json keys
  events.ts                    typed event names and payloads
public/assets/                 images, audio, atlases, tilemaps
tests/
  rules/scoring.test.ts
  e2e/boot.spec.ts
```

Dependency direction: `scenes → prefabs, systems → rules`; `rules/` never imports Phaser.

## Conventions

- One scene per file, registered in `main.ts`; scenes talk through the event bus (`events.ts`) or the registry, never
  by reaching into each other's fields.
- Prefabs extend Phaser classes, add themselves to the scene in their constructor and own their animations.
- Asset keys come from `assets/keys.ts`; no string literal keys in scenes or prefabs.
- Game rules (score, waves, damage) are pure functions in `rules/`.
- Frame-rate independence: movement uses `delta`; physics through Arcade bodies.
- Objects that come and go use groups with pooling (`get`/`killAndHide`), not create/destroy every frame.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev | `pnpm dev` |
| Build | `pnpm build` |
| Typecheck | `pnpm exec tsc --noEmit` |
| Test | `pnpm test` |
| Lint | `pnpm lint` |

## Testing

- Vitest for `rules/` and `systems/` logic that can be separated from Phaser.
- One Playwright smoke test: the game boots, the menu appears, starting a game reaches `GameScene` without console errors.
- Manual playtest checklist per release (controls, pause, restart, audio).

## Quality gates

- `tsc --noEmit`, lint and tests green; `pnpm build` produces `dist/` with no warnings about missing assets.
- Bundle size reported on release; assets compressed (atlases, OGG/MP3).

## Dependencies

- Allowed: Phaser, Vite, the table above; Phaser plugins with a reason.
- Do NOT use: string asset keys scattered in code, scene-to-scene field access, rules inside prefabs or scenes,
  creating/destroying objects every frame instead of pooling.

## Rules for agents

- Add screens as scenes in their own file and register them in `main.ts`.
- Put every asset key in `assets/keys.ts` and load assets only in `PreloadScene`.
- Write game rules as pure functions in `rules/` with Vitest tests.
- Make prefabs own their setup and animations; scenes only place and wire them.
- Communicate between scenes with the typed events in `events.ts`.
- Use `delta` for time-based movement and Arcade physics for collisions.
- Pool frequently spawned objects with groups.
- Keep `GameScene` thin: orchestration only, no scoring or wave math inside.
- Run typecheck, tests and a build before finishing.
