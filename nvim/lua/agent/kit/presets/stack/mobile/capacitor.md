<!-- name: Capacitor (web to mobile) -->
<!-- desc: A TypeScript web app shipped to iOS and Android with Capacitor: Vite, Ionic optional, native plugins -->

# STACK.md: Capacitor (web to mobile)

## Summary

A mobile app built as a web app and shipped to iOS and Android with Capacitor. The UI is a Vite + TypeScript SPA (Ionic
components optional for native look); native capabilities (camera, storage, push, haptics) come through Capacitor plugins
behind small adapter modules, so the same code runs in the browser for development.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (strict) | One language, typed plugins |
| Shell | Capacitor 7 | Native iOS/Android projects you own |
| Build | Vite 8 | Fast dev, Rolldown builds |
| UI | Ionic Framework (React or vanilla web components) or your own components | Native-feeling widgets |
| State | Framework state + small stores | No global magic |
| Native | Official `@capacitor/*` plugins (Preferences, Camera, Haptics, Push Notifications) | Maintained |
| Testing | Vitest + Playwright (web) | Fast feedback |
| Lint | Biome | One tool |
| Package manager | pnpm | Strict, fast |
| Release | Xcode / Android Studio, or fastlane | Store builds |

## Project layout

```
src/
  main.ts
  app/
    router.ts
  features/
    notes/
      notes.page.ts               page component
      notes.store.ts
      notes.store.test.ts
  native/
    storage.ts                    Preferences adapter (web fallback: localStorage)
    camera.ts                     Camera adapter
    platform.ts                   Capacitor.isNativePlatform()
  ui/
capacitor.config.ts
ios/                              generated native project (committed)
android/                          generated native project (committed)
```

Dependency direction: `features → native adapters`; nothing outside `native/` imports `@capacitor/*`.

## Conventions

- Every plugin used through an adapter with a web fallback, so the app runs in a browser.
- Safe areas via CSS `env(safe-area-inset-*)`; touch targets ≥ 44 px.
- Native project changes (permissions, Info.plist, AndroidManifest) are committed and documented in the PR.

## Commands

| Task | Command |
| --- | --- |
| Install | `pnpm install` |
| Dev (web) | `pnpm dev` |
| Build web | `pnpm build` |
| Sync native | `pnpm cap sync` |
| Run iOS | `pnpm cap run ios` |
| Run Android | `pnpm cap run android` |
| Test | `pnpm vitest run` |

## Testing

- Stores and adapters unit-tested (plugins mocked); Playwright for web flows; a manual smoke test on one iOS and one Android device per release.

## Quality gates

- Typecheck, Biome, tests and `pnpm build` clean; `cap sync` leaves no uncommitted native changes unexplained.

## Dependencies

- Official Capacitor plugins first; community plugins need a maintenance check.
- Do NOT use: Cordova plugins when a Capacitor one exists, direct `window.Capacitor` calls outside adapters.

## Rules for agents

- Import `@capacitor/*` only in `src/native/`.
- Give every adapter a web fallback.
- Run `cap sync` after adding a plugin and commit the native changes.
- Request permissions at the moment they are needed, with a reason shown first.
- Respect safe areas and the hardware back button (Android).
- Keep bundle size small: lazy load pages.
- Never store secrets in the app bundle.
- Test offline behaviour for any feature that reads remote data.
