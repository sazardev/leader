<!-- name: i18next -->
<!-- desc: translations with i18next and JSON locale files, namespaces, plurals and typed keys -->
<!-- for: ts js ui !mobile -->

## Stack

| Internationalization | i18next (with the React/Vue/Svelte binding of the project), JSON locale files per namespace, ICU-style plurals | Mature, framework-agnostic translations with lazy loading |

## Project layout

```
src/i18n/index.ts              i18next init: fallbackLng, supported languages, namespaces, detection
src/locales/<lng>/<ns>.json    one JSON file per language and namespace (en/common.json, es/common.json)
```

## Conventions

- No user-facing string in code: every text is a key, named by feature (`checkout.pay_button`), never by its English text.
- The source language (`en`) is the reference; every key exists in every locale and CI fails on missing or unused keys (`i18next-parser`).
- Plurals use i18next's `_one` / `_other` suffixes and the `count` option; never build plurals with `if`.
- Interpolation uses `{{name}}` values; never concatenate translated fragments into a sentence.
- Dates, numbers and currencies go through `Intl` (`Intl.DateTimeFormat`, `Intl.NumberFormat`) with the active language.
- Namespaces are loaded per route; type the keys by declaring the resources in `i18next.d.ts`.
- Layout supports longer text and right-to-left (`dir` set from the language).

## Commands

| i18n extract | `npx i18next-parser` |

## Testing

- A test loads every locale and checks the same keys and the same `{{placeholders}}` exist everywhere.

## Rules for agents

- Never hardcode a visible string; add the key to every locale file.
- Never translate by machine without marking the key for review.
- Never put HTML or secrets in translation values; use `<Trans>` components for rich text.
