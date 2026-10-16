<!-- name: React Native + Expo -->
<!-- desc: Expo SDK, Expo Router, TypeScript, TanStack Query, Zustand, NativeWind, EAS, Jest + RNTL, Maestro -->

# STACK.md: React Native + Expo

## Summary

A cross-platform mobile app with React Native on the Expo managed workflow (prebuild when native code is needed).
File-based routing with Expo Router, server state in TanStack Query, the little client state there is in Zustand.
Code is organised by feature; screens in `app/` are thin and delegate to feature modules.

## Stack

| Layer | Choice | Why |
| --- | --- | --- |
| Language | TypeScript 7 (native `tsc` for type checking, `strict`; Babel/Metro only strip types) | Types across navigation, API and state |
| Runtime | React Native (New Architecture) via Expo SDK (latest stable) | Managed native modules, OTA updates |
| Routing | Expo Router (typed routes) | File-based, deep links, layouts |
| Server state | `@tanstack/react-query` | Caching, retries, background refresh |
| Client state | `zustand` | Small, explicit stores |
| Forms | `react-hook-form` + `zod` | Validation shared with API types |
| Styling | NativeWind (Tailwind for RN) or `StyleSheet` with theme tokens | Consistent tokens |
| HTTP | `fetch` wrapper (or `ky`) + generated types (OpenAPI) | Typed API client |
| Storage | `expo-secure-store` (tokens), `react-native-mmkv` (cache/flags) | Secure vs fast |
| Lists | `@shopify/flash-list` | Performance on long lists |
| Images | `expo-image` | Caching, placeholders |
| Build/deploy | EAS Build, EAS Submit, EAS Update | Signed builds and OTA in CI |
| Testing | Jest (`jest-expo`) + React Native Testing Library + MSW; Maestro e2e | Behaviour tests, real-device flows |
| Lint/format | ESLint (`eslint-config-expo`) + Prettier, `tsc --noEmit` | Strict CI |
| Monitoring | `@sentry/react-native` | Crashes and performance |

## Project layout

```
app/                              Expo Router: routes only, thin
  _layout.tsx                     providers (QueryClient, theme, auth gate)
  (auth)/sign-in.tsx
  (tabs)/_layout.tsx
  (tabs)/orders/index.tsx         renders <OrdersScreen /> from the feature
  (tabs)/orders/[id].tsx
src/
  features/
    orders/
      api/orders.api.ts           requests + response → domain mapping
      api/orders.queries.ts       useOrders, useOrder (query keys in one place)
      model/order.ts              types + zod schema
      components/OrderCard.tsx    one component per file
      screens/OrdersScreen.tsx
      store/orders.store.ts       zustand store (only if needed)
  shared/
    api/client.ts                 fetch wrapper: base URL, auth header, errors
    ui/                           design-system components (Button, Text, Screen)
    theme/tokens.ts               colors, spacing, typography
    hooks/
  config/env.ts                   typed EXPO_PUBLIC_* config
e2e/                              Maestro flows (*.yaml)
app.config.ts, eas.json
```

Dependency direction: `app → features → shared`. A feature never imports another feature's internals; shared code moves to `shared/`.

## Conventions

- Route files only compose: they import a screen from `src/features/*/screens`.
- One component per file, named export, `PascalCase.tsx`; hooks `useX.ts`; pure helpers in `*.ts`.
- Server data lives only in React Query; never copy it into Zustand.
- Query keys come from one factory per feature (`orderKeys.detail(id)`).
- API responses are parsed with zod at the boundary; components receive domain types.
- Styling only through tokens (NativeWind config or `theme/tokens.ts`); no magic numbers.
- Platform differences in `*.ios.tsx` / `*.android.tsx` or `Platform.select`, never scattered `if`s.
- New feature = `src/features/<name>/{api,model,components,screens}` + route files + tests + Maestro flow if critical.

## Commands

| Task | Command |
| --- | --- |
| Install | `npx expo install` (native-compatible versions) / `pnpm install` |
| Dev | `npx expo start` |
| Run native | `npx expo run:ios` / `npx expo run:android` |
| Test | `pnpm test` (jest-expo) |
| Typecheck | `pnpm tsc --noEmit` |
| Lint | `pnpm lint` (`expo lint`) |
| Format | `pnpm prettier --write .` |
| E2E | `maestro test e2e/` |
| Doctor | `npx expo-doctor` |
| Build | `eas build --profile preview --platform all` |
| OTA update | `eas update --branch preview --message "..."` |

## Testing

- Components and screens with RNTL: query by role/label, interact with `userEvent`, assert what the user sees.
- Network mocked with MSW; React Query with a fresh `QueryClient` per test (retries off).
- Pure logic (mappers, stores, validators) with plain Jest unit tests.
- Maestro flows for sign-in and the critical paths, run on EAS or CI emulators.
- No snapshot tests of whole screens.

## Quality gates

- `tsc --noEmit`, ESLint and Prettier clean; `expo-doctor` without errors.
- Jest passes; Maestro critical flows pass before a store release.
- No `any` without a comment; no `console.log` in committed code.
- OTA updates only for JS changes compatible with the current runtime version (`runtimeVersion` policy).

## Dependencies

- Install native-backed packages with `npx expo install` so versions match the SDK.
- Prefer Expo modules (`expo-*`) over community equivalents.
- Do NOT use: Redux for server data, Axios plus fetch in parallel, `AsyncStorage` for secrets, libraries that require ejecting without a config plugin, `moment` (use `date-fns` or `Intl`).

## Rules for agents

- Keep route files thin: no data fetching or business logic in `app/`.
- Never store tokens outside `expo-secure-store`.
- Use `FlashList` for lists that can grow; never `ScrollView` + `map` for data lists.
- Every screen handles loading, error (with retry) and empty states.
- Validate all API responses with zod at the API layer.
- Every interactive element has `accessibilityRole` and `accessibilityLabel`.
- Read config only from `config/env.ts` (`EXPO_PUBLIC_*`); never put secrets in the app.
- After adding a native dependency, run `npx expo prebuild --clean` locally and say so in the PR (new build required, no OTA).
- Invalidate the relevant query keys after mutations instead of refetching everything.
