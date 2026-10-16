<!-- name: TypeScript 7 (native) -->
<!-- desc: the native compiler (stable since July 2026): `tsc` from typescript 7, ~10x faster type checking -->
<!-- for: ts -->
<!-- default: lang:typescript lang:bun lang:node -->

## Stack

| Language | TypeScript 7 (native compiler, `strict` + `noUncheckedIndexedAccess` + `exactOptionalPropertyTypes`) | Same language, type checking about 10x faster: checks stay cheap enough to run on every save and in CI |
| Typecheck | `tsc --noEmit` from the `typescript` 7 package (the bundler strips types, tsc only checks) | One source of truth for types, independent of the build |

## Commands

| Typecheck | `tsc --noEmit` |
| Typecheck (watch) | `tsc --noEmit --watch` |

## Conventions

- `tsconfig.json` keeps `strict: true`, `noUncheckedIndexedAccess`, `noImplicitOverride`, `verbatimModuleSyntax` and `isolatedModules` on; a file never lowers them locally.
- Types are checked by `tsc`, code is emitted by the bundler (Vite, the framework, Bun): never rely on `tsc` output files.
- Before upgrading, check that every tool that loads the compiler API (typescript-eslint, framework plugins, editor extensions) states TypeScript 7 support; if one lags, keep that tool on its supported version and say so in a comment next to the dependency.

## Quality gates

- `tsc --noEmit` exits 0 in CI; no `@ts-ignore` (use `@ts-expect-error` with a reason).

## Rules for agents

- Never weaken `tsconfig.json` (turning off `strict` or a strict flag) to make a change compile: fix the types.
- Never use `any`; use `unknown` and narrow it, or write the type.
- Never add `@ts-ignore`; `@ts-expect-error` only with a one-line reason.
